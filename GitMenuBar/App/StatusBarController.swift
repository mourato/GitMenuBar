//
//  StatusBarController.swift
//  GitMenuBar
//

import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

// swiftlint:disable file_length
@MainActor
final class StatusBarController: ObservableObject {
    private enum Constants {
        static let statusIconPointSize = NSSize(width: 16, height: 16)
        static let windowInitialSize = NSSize(width: 700, height: 720)
        static let windowMinimumSize = NSSize(width: 550, height: 640)
        static let windowPresentationDuration: TimeInterval = 0.20
        static let windowPresentationReducedMotionDuration: TimeInterval = 0.01
        static let autoHideBlurEvaluationDelay: TimeInterval = 0.08
        static let windowAutosaveName = NSWindow.FrameAutosaveName("GitMenuBar.MainWindow")
        static let screenCaptureUIBundleIdentifier = "com.apple.screencaptureui"
        static let appFocusedShortcutNames: [KeyboardShortcuts.Name] = [
            .commandPalette, .commit, .sync, .atomicCommits, .push, .branchManagement, .createBranch
        ]
    }

    private struct WindowOpenTrace {
        let id: Int
        let startedAt: CFAbsoluteTime
        let trigger: String
    }

    private enum WindowPlacementStrategy {
        case statusItemAnchor
        case mousePointerMonitor
    }

    private enum MainWindowPresentationState {
        case hidden
        case presenting
        case visible
        case dismissing
    }

    var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    var contextMenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()
    private var baseStatusImage: NSImage?
    private var remoteExistenceByPath: [String: RemoteExistenceState] = [:]
    private var nextWindowOpenTraceID = 0
    private var hasPositionedWindowInitially = false
    private var isAutoHideSuspended = false
    private var mainWindowPresentationState: MainWindowPresentationState = .hidden
    private var mainWindowTransitionID = 0
    private var shortcutQueue = MainWindowShortcutQueue()

    private let windowDelegate = MainWindowLifecycleDelegate()

    let gitManager = GitManager()
    let loginItemManager = LoginItemManager()
    let githubAuthManager: GitHubAuthManager
    let appCommandCenter: AppCommandCenter
    let aiProviderStore = AIProviderStore()
    let aiKeychainStore: any AIAPIKeyStore
    let aiCommitMessageService = AICommitMessageService()
    let shortcutActionBridge = MainMenuShortcutActionBridge()
    let presentationModel = MainMenuPresentationModel()
    let usageQuotaStore: UsageQuotaStore
    let projectMonitor = ProjectMonitorStore()

    lazy var aiCommitCoordinator = AICommitCoordinator(
        providerStore: aiProviderStore,
        keychainStore: aiKeychainStore,
        messageService: aiCommitMessageService,
        gitManager: gitManager
    )
    lazy var actionCoordinator = MainMenuActionCoordinator(
        gitManager: gitManager,
        aiCommitCoordinator: aiCommitCoordinator
    )
    lazy var commitHistoryEditCoordinator = CommitHistoryEditCoordinator(
        gitManager: gitManager,
        aiCommitCoordinator: aiCommitCoordinator
    )
    private lazy var settingsWindowController = AppSettingsWindowController(
        gitManager: gitManager,
        loginItemManager: loginItemManager,
        githubAuthManager: githubAuthManager,
        aiProviderStore: aiProviderStore,
        aiCommitCoordinator: aiCommitCoordinator,
        usageQuotaStore: usageQuotaStore,
        onSetAutoHideSuspended: { [weak self] suspended in
            self?.setAutoHideSuspended(suspended)
        }
    )

    init(githubAuthManager: GitHubAuthManager, appCommandCenter: AppCommandCenter) {
        self.githubAuthManager = githubAuthManager
        self.appCommandCenter = appCommandCenter
        if AppExecutionContext.usesEphemeralCredentialStores {
            aiKeychainStore = InMemoryAIAPIKeyStore()
        } else {
            let cachedStore = CachedAIAPIKeyStore.shared
            try? cachedStore.preloadAllKeys() // Retry on demand if the Keychain is locked.
            aiKeychainStore = cachedStore
        }
        usageQuotaStore = UsageQuotaStore(providers: [CodexUsageProvider(), CursorUsageProvider(), OpenRouterUsageProvider(keyStore: aiKeychainStore)])

        // Wire up token provider for git push operations
        gitManager.tokenProvider = { [weak githubAuthManager] in
            githubAuthManager?.storedTokenSnapshot()
        }

        // Wire up GitHub API client for checking repo existence
        gitManager.githubAPIClient = GitHubAPIClient(authManager: githubAuthManager)
        appCommandCenter.performInvocation = { [weak self] invocation in
            self?.performAppCommand(invocation)
        }

        setupStatusItem()
        setupContextMenu()
        setupMainWindow()
        setupBadgeObservation()
        setupShortcutHandlers()
        setupAuthenticationObservation()
        setupAppCommandObservation()

        projectMonitor.seed(
            currentPath: UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? "",
            recentProjects: RecentProjectsStore().recentProjects()
        )
        refreshAppCommands()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 20)
        baseStatusImage = StatusItemBadgeRenderer.makeBaseStatusImage(iconSize: Constants.statusIconPointSize)

        guard let button = statusItem?.button else { return }
        button.image = baseStatusImage
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self

        updateStatusItemBadge(count: projectMonitor.attentionCount)
    }

    private func updateStatusItemBadge(count: Int) {
        guard let button = statusItem?.button else { return }

        guard count > 0 else {
            button.image = baseStatusImage
            return
        }

        button.image = StatusItemBadgeRenderer.makeBadgedImage(
            count: count,
            baseStatusImage: baseStatusImage,
            iconSize: Constants.statusIconPointSize
        )
    }

    private func setupBadgeObservation() {
        projectMonitor.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemBadge(count: self?.projectMonitor.attentionCount ?? 0) }
            .store(in: &cancellables)
    }

    private func setupShortcutHandlers() {
        KeyboardShortcuts.onKeyDown(for: .togglePopover) { [weak self] in
            Task { @MainActor in
                self?.toggleMainWindowFromShortcut()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .commandPalette) { [weak self] in
            Task { @MainActor in
                self?.handleCommandPaletteShortcut()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .commit) { [weak self] in
            Task { @MainActor in
                self?.handleActionShortcut(.commit)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .sync) { [weak self] in
            Task { @MainActor in
                self?.handleActionShortcut(.sync)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .atomicCommits) { [weak self] in
            Task { @MainActor in
                self?.handleActionShortcut(.atomicCommits)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .push) { [weak self] in
            Task { @MainActor in
                self?.appCommandCenter.perform(.push)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .branchManagement) { [weak self] in
            Task { @MainActor in
                self?.appCommandCenter.perform(.branchManagement)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .createBranch) { [weak self] in
            Task { @MainActor in
                self?.appCommandCenter.perform(.createBranch)
            }
        }

        setupActionShortcutScopeObservation()
    }

    private func setupActionShortcutScopeObservation() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { _ in
                KeyboardShortcuts.enable(Constants.appFocusedShortcutNames)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { _ in
                KeyboardShortcuts.disable(Constants.appFocusedShortcutNames)
            }
            .store(in: &cancellables)

        updateActionShortcutScope(isAppActive: NSApp.isActive)
    }

    private func updateActionShortcutScope(isAppActive: Bool) {
        if isAppActive {
            KeyboardShortcuts.enable(Constants.appFocusedShortcutNames)
            return
        }

        KeyboardShortcuts.disable(Constants.appFocusedShortcutNames)
    }

    private func setupAuthenticationObservation() {
        githubAuthManager.$isAuthenticating
            .receive(on: RunLoop.main)
            .sink { [weak self] isAuthenticating in
                self?.setAutoHideSuspended(isAuthenticating)
            }
            .store(in: &cancellables)
    }

    private func setupAppCommandObservation() {
        let publishers: [AnyPublisher<Void, Never>] = [
            gitManager.$stagedFiles.map { _ in () }.eraseToAnyPublisher(),
            gitManager.$changedFiles.map { _ in () }.eraseToAnyPublisher(),
            gitManager.$isAheadOfRemote.map { _ in () }.eraseToAnyPublisher(),
            gitManager.$isRemoteAhead.map { _ in () }.eraseToAnyPublisher(),
            gitManager.$remoteUrl.map { _ in () }.eraseToAnyPublisher(),
            githubAuthManager.$isAuthenticated.map { _ in () }.eraseToAnyPublisher(),
            projectMonitor.$snapshots.map { _ in () }.eraseToAnyPublisher(),
            presentationModel.$route.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(
                for: UserDefaults.didChangeNotification,
                object: UserDefaults.standard
            )
            .map { _ in () }
            .eraseToAnyPublisher()
        ]

        Publishers.MergeMany(publishers)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.refreshAppCommands()
            }
            .store(in: &cancellables)
    }

    private func setupContextMenu() {
        contextMenu = NSMenu()
        rebuildContextMenu()
    }

    private func setupMainWindow() {
        let contentRect = NSRect(origin: .zero, size: Constants.windowInitialSize)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        configureMainWindowAppearance(window)
        window.title = "GitMenuBar"
        window.isReleasedWhenClosed = false
        window.setContentSize(Constants.windowInitialSize)
        window.contentMinSize = Constants.windowMinimumSize
        window.setFrameAutosaveName(Constants.windowAutosaveName)
        hasPositionedWindowInitially = window.setFrameUsingName(Constants.windowAutosaveName, force: false)
        normalizeMainWindowSize(window)

        let contentController = WorkbenchWindowChrome.makeHostedContentController(rootView: makeRootView())
        window.contentViewController = contentController
        WorkbenchWindowChrome.configureTransparentWindow(window)

        windowDelegate.onShouldClose = { [weak self] in
            self?.hideMainWindow()
            return false
        }
        windowDelegate.onDidResignKey = { [weak self] in
            self?.handleMainWindowDidResignKey()
        }
        windowDelegate.onDidMoveOrResize = { [weak self] in
            self?.persistMainWindowFrameIfPossible()
        }

        window.delegate = windowDelegate

        mainWindow = window
    }

    private func configureMainWindowAppearance(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.hasShadow = true
        window.isMovableByWindowBackground = false
    }

    private func makeRootView() -> AnyView {
        let rootView = MainMenuView(
            closeWindow: { [weak self] in
                self?.hideMainWindow()
            },
            openSettingsWindow: { [weak self] in
                self?.openSettingsWindow()
            },
            setAutoHideSuspended: { [weak self] suspended in
                self?.setAutoHideSuspended(suspended)
            }
        )
        .environmentObject(gitManager)
        .environmentObject(loginItemManager)
        .environmentObject(githubAuthManager)
        .environmentObject(aiProviderStore)
        .environmentObject(aiCommitCoordinator)
        .environmentObject(actionCoordinator)
        .environmentObject(commitHistoryEditCoordinator)
        .environmentObject(shortcutActionBridge)
        .environmentObject(presentationModel)
        .environmentObject(usageQuotaStore)
        .environmentObject(projectMonitor)

        return AnyView(rootView)
    }

    private func setAutoHideSuspended(_ suspended: Bool) {
        isAutoHideSuspended = suspended
    }

    private func handleMainWindowDidResignKey() {
        guard shouldAutoHideOnBlur, !isMainWindowPresentingSheet else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.autoHideBlurEvaluationDelay) { [weak self] in
            guard let self,
                  shouldAutoHideOnBlur,
                  !self.isMainWindowPresentingSheet,
                  !self.isSystemScreenCaptureUIFrontmost
            else { return }

            hideMainWindow()
        }
    }

    private var isMainWindowPresentingSheet: Bool {
        mainWindow?.attachedSheet != nil
    }

    private var shouldAutoHideOnBlur: Bool {
        MainWindowPreferences.isAutoHideOnBlurEnabled() && !isAutoHideSuspended
    }

    private var isSystemScreenCaptureUIFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Constants.screenCaptureUIBundleIdentifier
    }

    private var isMainWindowVisible: Bool {
        guard mainWindow?.isVisible == true else { return false }
        return mainWindowPresentationState != .dismissing
    }

    private func handleActionShortcut(_ action: MainMenuShortcutAction) {
        shortcutQueue.enqueue(action)

        if isMainWindowVisible, presentationModel.route == .main {
            flushPendingShortcutActionsIfReady()
            return
        }

        let trace = beginWindowOpenTrace(trigger: "shortcut_\(describe(shortcutAction: action))")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false

        openMainWindow(
            route: .main,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: true,
            trace: trace
        )
    }

    private func handleCommandPaletteShortcut() {
        if isMainWindowVisible {
            presentationModel.showMain(requestCommitFocus: false)
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                self?.presentationModel.requestCommandPalettePresentation()
            }
            return
        }

        let trace = beginWindowOpenTrace(trigger: "shortcut_commandPalette")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false

        openMainWindow(
            route: .main,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: true,
            trace: trace
        )
        DispatchQueue.main.async { [weak self] in
            self?.presentationModel.requestCommandPalettePresentation()
        }
    }

    private func flushPendingShortcutActionsIfReady() {
        let actions = shortcutQueue.dequeueAllIfReady(
            isWindowVisible: isMainWindowVisible,
            isMainRoute: presentationModel.route == .main
        )

        guard !actions.isEmpty else { return }

        for action in actions {
            shortcutActionBridge.send(action)
        }
    }

    @objc private func handleStatusItemClick(_: AnyObject?) {
        guard let currentEvent = NSApp.currentEvent else {
            toggleMainWindow(nil)
            return
        }

        switch currentEvent.type {
        case .rightMouseUp:
            showContextMenu()
        case .leftMouseUp where currentEvent.modifierFlags.contains(.control):
            showContextMenu()
        default:
            toggleMainWindow(nil)
        }
    }

    private func showContextMenu() {
        guard let contextMenu, let button = statusItem?.button else { return }

        rebuildContextMenu()
        statusItem?.menu = contextMenu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func toggleMainWindowFromShortcut() {
        let placementStrategy: WindowPlacementStrategy = MainWindowPreferences
            .isToggleShortcutUsingMouseMonitorEnabled()
            ? .mousePointerMonitor
            : .statusItemAnchor

        toggleMainWindow(placementStrategy: placementStrategy)
    }

    @objc func toggleMainWindow(_: AnyObject?) {
        toggleMainWindow(placementStrategy: .statusItemAnchor)
    }

    private func toggleMainWindow(placementStrategy: WindowPlacementStrategy) {
        if isMainWindowVisible {
            hideMainWindow()
            return
        }

        let trace = beginWindowOpenTrace(trigger: "toggle")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false
        let initialRoute = initialRoute(for: repositoryPath, isGitRepo: isGitRepo)

        openMainWindow(
            route: initialRoute,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: shouldRefreshAfterPresenting(route: initialRoute),
            trace: trace,
            placementStrategy: placementStrategy
        )
    }

    private func openMainWindow(
        route: MainMenuRoute,
        repositoryPath: String?,
        isGitRepo: Bool,
        shouldRefreshAfterPresentation: Bool,
        trace: WindowOpenTrace,
        placementStrategy: WindowPlacementStrategy = .statusItemAnchor
    ) {
        presentationModel.prepareForPresentation(route: route, requestCommitFocus: route == .main)
        if route != .main {
            presentationModel.clearCreateRepoSuggestion()
        }

        logWindowOpen(trace, message: "route resolved to \(describe(route: route))")
        presentMainWindow(trace: trace, placementStrategy: placementStrategy)

        if shouldRefreshAfterPresentation {
            refreshMainWindowData(trace: trace)
        } else {
            presentationModel.finishRefresh()
            flushPendingShortcutActionsIfReady()
        }

        validateRemoteIfNeeded(path: repositoryPath, isGitRepo: isGitRepo, trace: trace)
    }

    private func presentMainWindow(trace: WindowOpenTrace, placementStrategy: WindowPlacementStrategy) {
        guard let mainWindow else { return }

        if mainWindowPresentationState == .dismissing {
            activateAndShowMainWindow(mainWindow, trace: trace)
            refreshUsageQuotaOnWindowPresented()
            return
        }

        if mainWindowPresentationState == .presenting || mainWindowPresentationState == .visible {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            refreshUsageQuotaOnWindowPresented()
            return
        }

        if restoreMainWindowFrameIfAvailable(mainWindow) {
            normalizeMainWindowSize(mainWindow)
            hasPositionedWindowInitially = true
        } else {
            switch placementStrategy {
            case .mousePointerMonitor:
                if let screen = screenContainingMousePointer() {
                    positionMainWindow(on: screen, window: mainWindow)
                    hasPositionedWindowInitially = true
                } else if !hasPositionedWindowInitially {
                    positionMainWindowRelativeToStatusItem(mainWindow)
                    hasPositionedWindowInitially = true
                }
            case .statusItemAnchor:
                if !hasPositionedWindowInitially {
                    positionMainWindowRelativeToStatusItem(mainWindow)
                    hasPositionedWindowInitially = true
                }
            }
        }

        mainWindow.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindowPresentationState = .presenting
        animateMainWindowAlpha(to: 1, trace: trace)
        refreshUsageQuotaOnWindowPresented()
    }

    private func refreshUsageQuotaOnWindowPresented() {
        usageQuotaStore.refresh(reason: .windowPresented)
    }

    private func activateAndShowMainWindow(_ window: NSWindow, trace: WindowOpenTrace) {
        let transitionID = beginMainWindowTransition()
        mainWindowPresentationState = .presenting
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        animateMainWindowAlpha(to: 1, trace: trace, transitionID: transitionID)
    }

    private func animateMainWindowAlpha(
        to alpha: CGFloat,
        trace: WindowOpenTrace? = nil,
        transitionID: Int? = nil
    ) {
        guard let mainWindow else { return }

        let transitionID = transitionID ?? beginMainWindowTransition()
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? Constants.windowPresentationReducedMotionDuration
            : Constants.windowPresentationDuration

        guard duration > 0 else {
            mainWindow.alphaValue = alpha
            completeMainWindowPresentation(to: alpha, trace: trace, transitionID: transitionID)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            mainWindow.animator().alphaValue = alpha
        } completionHandler: { [weak self, weak mainWindow] in
            guard let self, mainWindow != nil else { return }
            Task { @MainActor in
                self.completeMainWindowPresentation(to: alpha, trace: trace, transitionID: transitionID)
            }
        }
    }

    private func completeMainWindowPresentation(to alpha: CGFloat, trace: WindowOpenTrace?, transitionID: Int) {
        guard transitionID == mainWindowTransitionID, let mainWindow else { return }

        if alpha == 0 {
            mainWindow.orderOut(nil)
            mainWindow.alphaValue = 0
            mainWindowPresentationState = .hidden
            if let trace {
                logWindowOpen(trace, message: "window hidden")
            }
        } else {
            mainWindowPresentationState = .visible
            if let trace {
                logWindowOpen(trace, message: "window presentation completed")
            }
        }
    }

    private func beginMainWindowTransition() -> Int {
        mainWindowTransitionID += 1
        return mainWindowTransitionID
    }

    private func positionMainWindowRelativeToStatusItem(_ window: NSWindow) {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else {
            window.center()
            return
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectInScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let visibleFrame = screen.visibleFrame

        var originX = buttonRectInScreen.maxX - window.frame.width
        var originY = buttonRectInScreen.minY - window.frame.height - 8

        originX = min(max(originX, visibleFrame.minX + 8), visibleFrame.maxX - window.frame.width - 8)

        if originY < visibleFrame.minY + 8 {
            originY = visibleFrame.maxY - window.frame.height - 20
        }

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func screenContainingMousePointer() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main
    }

    private func positionMainWindow(on screen: NSScreen, window: NSWindow) {
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 12

        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - window.frame.width - margin
        let minY = visibleFrame.minY + margin
        let maxY = visibleFrame.maxY - window.frame.height - margin

        let originX = max(minX, maxX)
        let originY = max(minY, maxY)

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func normalizeMainWindowSize(_ window: NSWindow) {
        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        let normalizedContentSize = NSSize(
            width: max(currentContentRect.width, Constants.windowMinimumSize.width),
            height: max(currentContentRect.height, Constants.windowMinimumSize.height)
        )

        guard normalizedContentSize != currentContentRect.size else { return }
        window.setContentSize(normalizedContentSize)
    }

    private func hideMainWindow() {
        guard let mainWindow, mainWindow.isVisible else {
            mainWindowPresentationState = .hidden
            return
        }

        guard mainWindowPresentationState != .dismissing else { return }

        persistMainWindowFrame(mainWindow)
        mainWindowPresentationState = .dismissing
        animateMainWindowAlpha(to: 0)
    }

    private func persistMainWindowFrame(_ window: NSWindow) {
        window.saveFrame(usingName: Constants.windowAutosaveName)
    }

    private func persistMainWindowFrameIfPossible() {
        guard let mainWindow else { return }
        persistMainWindowFrame(mainWindow)
    }

    private func restoreMainWindowFrameIfAvailable(_ window: NSWindow) -> Bool {
        window.setFrameUsingName(Constants.windowAutosaveName, force: false)
    }

    private func openSettingsWindow() {
        settingsWindowController.show()
    }

    func showSettingsWindow() {
        openSettingsWindow()
    }

    /// Opens the main window programmatically (used when app is launched with a folder path)
    func openMainWindow() {
        if isMainWindowVisible {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let trace = beginWindowOpenTrace(trigger: "programmatic")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false
        let initialRoute = initialRoute(for: repositoryPath, isGitRepo: isGitRepo)

        openMainWindow(
            route: initialRoute,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: shouldRefreshAfterPresenting(route: initialRoute),
            trace: trace
        )
    }

    private func presentMainWindowForActionFeedback() {
        if isMainWindowVisible {
            presentationModel.showMain(requestCommitFocus: true)
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
            flushPendingShortcutActionsIfReady()
            return
        }

        let trace = beginWindowOpenTrace(trigger: "context_action")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false

        openMainWindow(
            route: .main,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: true,
            trace: trace
        )
    }

    /// Opens the main window directly showing the create repo view (used when opening a non-git folder)
    func openMainWindowWithCreateRepo(path: String) {
        let trace = beginWindowOpenTrace(trigger: "create_repo")
        openMainWindow(
            route: .createRepo(path: path),
            repositoryPath: path,
            isGitRepo: gitManager.isGitRepository(at: path),
            shouldRefreshAfterPresentation: false,
            trace: trace
        )
    }

    private func currentRepositoryPath() -> String? {
        let path = UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
        return path.isEmpty ? nil : path
    }

    private func refreshAppCommands() {
        let hasWorkingTreeChanges = !gitManager.stagedFiles.isEmpty || !gitManager.changedFiles.isEmpty

        let snapshot = AppCommandResolver.resolveSnapshot(
            context: AppCommandContext(
                actionState: StatusBarContextMenuActionState.resolve(
                    hasCommitWork: actionCoordinator.hasWorkingTreeChanges,
                    hasSyncWork: actionCoordinator.hasSyncWork,
                    canAutoCommit: actionCoordinator.canAutoCommit,
                    canSync: actionCoordinator.canSync
                ),
                syncActionTitle: actionCoordinator.syncActionTitle,
                currentRepoPath: currentRepositoryPath() ?? "",
                remoteUrl: gitManager.remoteUrl,
                recentProjects: RecentProjectsStore().recentProjects(),
                isGitHubAuthenticated: githubAuthManager.isAuthenticated,
                hasWorkingTreeChanges: hasWorkingTreeChanges,
                canDoAtomicCommits: hasWorkingTreeChanges && aiCommitCoordinator.isReadyForGeneration,
                isBehindRemote: gitManager.isBehindRemote,
                isAheadOfRemote: gitManager.isAheadOfRemote,
                canShowBranchManagement: !(currentRepositoryPath()?.isEmpty ?? true),
                currentBranch: gitManager.currentBranch,
                defaultBranchName: gitManager.defaultBranchName,
                monitoredProjects: Array(projectMonitor.snapshots.values)
            )
        )

        appCommandCenter.apply(snapshot)
    }

    private func performAppCommand(_ invocation: AppCommandInvocation) {
        switch invocation {
        case let .command(commandID):
            performAppCommand(commandID)
        case let .recentProject(path):
            selectRepository(path)
        }
    }

    private func performAppCommand(_ commandID: AppCommandID) {
        if handleCoordinatorCommand(commandID) {
            return
        }

        let handlers: [AppCommandID: () -> Void] = [
            .openWindow: openMainWindow,
            .showSettings: openSettingsWindow,
            .showCommandPalette: handleCommandPaletteShortcut,
            .chooseRepository: chooseRepository,
            .addProject: chooseRepository,
            .refreshAllProjects: projectMonitor.refreshAll,
            .fetchAllProjects: projectMonitor.fetchAll,
            .revealRepositoryInFinder: revealCurrentRepositoryInFinder,
            .openRepositoryOnGitHub: openCurrentRepositoryOnGitHub,
            .showRepositoryOptions: presentRepositoryOptions,
            .atomicCommits: openMainWindow,
            .branchManagement: openMainWindow,
            .createBranch: openMainWindow,
            .mergeToDefault: openMainWindow,
            .helpRepository: { self.open(urlString: "https://github.com/saihgupr/GitMenuBar") },
            .reportIssue: { self.open(urlString: "https://github.com/saihgupr/GitMenuBar/issues/new/choose") },
            .quit: { NSApplication.shared.terminate(nil) }
        ]
        handlers[commandID]?()
    }

    private func handleCoordinatorCommand(_ commandID: AppCommandID) -> Bool {
        switch commandID {
        case .commit:
            performCommitCommand(shouldPushAfterCommit: false)
        case .commitAndPush:
            performCommitCommand(shouldPushAfterCommit: true)
        case .sync:
            performSyncCommand()
        case .push:
            performPushCommand()
        case .pull:
            performPullCommand()
        default:
            return false
        }

        return true
    }

    private func performCommitCommand(shouldPushAfterCommit: Bool) {
        Task { @MainActor in
            let result = await actionCoordinator.performCommit(
                commentText: "",
                forceAutomaticMessage: true,
                shouldPushAfterCommit: shouldPushAfterCommit
            )
            if result.shouldOpenPopover {
                presentMainWindowForActionFeedback()
            }
        }
    }

    private func performSyncCommand() {
        Task { @MainActor in
            let result = await actionCoordinator.performSync()
            if result.shouldOpenPopover {
                presentMainWindowForActionFeedback()
            }
        }
    }

    private func performPushCommand() {
        Task { @MainActor in
            let result = await actionCoordinator.performSync()
            if result.shouldOpenPopover {
                presentMainWindowForActionFeedback()
            }
        }
    }

    private func performPullCommand() {
        Task { @MainActor in
            let result = await actionCoordinator.syncWithRemote(rebase: false)
            if result.shouldOpenPopover {
                presentMainWindowForActionFeedback()
            }
        }
    }

    private func chooseRepository() {
        setAutoHideSuspended(true)
        DirectoryPickerService().selectDirectory(activateApp: true) { [weak self] selectedPath in
            guard let self else { return }
            setAutoHideSuspended(false)

            guard let selectedPath else { return }
            selectRepository(selectedPath)
        }
    }

    private func selectRepository(_ path: String) {
        let wasVisible = isMainWindowVisible
        UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
        RecentProjectsStore().add(path)
        if gitManager.isGitRepository(at: path) {
            projectMonitor.add(path: path)
        }
        gitManager.resetSelectedRepositoryState()
        refreshAppCommands()

        if !gitManager.isGitRepository(at: path), githubAuthManager.isAuthenticated {
            openMainWindowWithCreateRepo(path: path)
            return
        }

        openMainWindow()
        guard wasVisible else { return }

        presentationModel.startRefresh()
        gitManager.refreshSelectedRepository(path: path, includeReflogHistory: false) {
            self.presentationModel.finishRefresh()
        }
    }

    private func revealCurrentRepositoryInFinder() {
        guard let path = currentRepositoryPath() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func openCurrentRepositoryOnGitHub() {
        guard let reference = GitHubRemoteURLParser.parse(gitManager.remoteUrl) else {
            return
        }

        open(urlString: "https://github.com/\(reference.owner)/\(reference.repository)")
    }

    private func presentRepositoryOptions() {
        if isMainWindowVisible {
            presentationModel.showMain(requestCommitFocus: false)
            presentationModel.requestRepositoryOptionsPresentation()
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let trace = beginWindowOpenTrace(trigger: "repository_options")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false
        openMainWindow(
            route: .main,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: true,
            trace: trace
        )
        DispatchQueue.main.async { [weak self] in
            self?.presentationModel.requestRepositoryOptionsPresentation()
        }
    }

    private func open(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func initialRoute(for repositoryPath: String?, isGitRepo: Bool) -> MainMenuRoute {
        guard let repositoryPath, isGitRepo, githubAuthManager.isAuthenticated else {
            return .main
        }

        switch remoteExistenceByPath[repositoryPath] ?? .unknown {
        case .missing:
            return .createRepo(path: repositoryPath)
        case .unknown, .checking, .exists:
            return .main
        }
    }

    private func shouldRefreshAfterPresenting(route: MainMenuRoute) -> Bool {
        if case .createRepo = route {
            return false
        }

        return true
    }

    private func refreshMainWindowData(trace: WindowOpenTrace) {
        presentationModel.startRefresh()
        logWindowOpen(trace, message: "refresh started")

        gitManager.refreshSelectedRepository { [weak self] in
            guard let self else { return }

            presentationModel.finishRefresh()
            flushPendingShortcutActionsIfReady()
            logWindowOpen(trace, message: "refresh completed")
        }
    }

    private func validateRemoteIfNeeded(path: String?, isGitRepo: Bool, trace: WindowOpenTrace) {
        guard let path, isGitRepo, githubAuthManager.isAuthenticated else {
            presentationModel.clearCreateRepoSuggestion()
            return
        }

        let cachedState = remoteExistenceByPath[path] ?? .unknown
        guard cachedState == .unknown else {
            if cachedState == .exists {
                presentationModel.clearCreateRepoSuggestion()
            } else if cachedState == .missing, presentationModel.route == .main {
                presentationModel.suggestCreateRepo(path: path)
            }
            return
        }

        remoteExistenceByPath[path] = .checking
        logWindowOpen(trace, message: "remote validation started")

        gitManager.remoteRepositoryExists(at: path) { [weak self] exists in
            guard let self else { return }

            remoteExistenceByPath[path] = exists ? .exists : .missing
            logWindowOpen(trace, message: "remote validation completed (\(exists ? "exists" : "missing"))")

            guard currentRepositoryPath() == path else { return }

            if exists {
                presentationModel.clearCreateRepoSuggestion()
                return
            }

            if presentationModel.route == .main {
                presentationModel.suggestCreateRepo(path: path)
            }
        }
    }

    private func beginWindowOpenTrace(trigger: String) -> WindowOpenTrace {
        nextWindowOpenTraceID += 1
        let trace = WindowOpenTrace(
            id: nextWindowOpenTraceID,
            startedAt: CFAbsoluteTimeGetCurrent(),
            trigger: trigger
        )

        print("[WindowOpen #\(trace.id)] trigger=\(trigger) +0ms")
        return trace
    }

    private func logWindowOpen(_ trace: WindowOpenTrace, message: String) {
        let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - trace.startedAt) * 1000)
        print("[WindowOpen #\(trace.id)] trigger=\(trace.trigger) +\(elapsedMilliseconds)ms \(message)")
    }

    private func describe(route: MainMenuRoute) -> String {
        switch route {
        case .main:
            "main"
        case let .createRepo(path):
            "createRepo(\(path))"
        case let .historyDetail(commitID):
            "historyDetail(\(commitID))"
        }
    }

    private func describe(shortcutAction: MainMenuShortcutAction) -> String {
        switch shortcutAction {
        case .commit:
            "commit"
        case .sync:
            "sync"
        case .atomicCommits:
            "atomicCommits"
        }
    }
}

private final class MainWindowLifecycleDelegate: NSObject, NSWindowDelegate {
    var onShouldClose: (() -> Bool)?
    var onDidResignKey: (() -> Void)?
    var onDidMoveOrResize: (() -> Void)?

    func windowShouldClose(_: NSWindow) -> Bool {
        onShouldClose?() ?? true
    }

    func windowDidResignKey(_: Notification) {
        onDidResignKey?()
    }

    func windowDidMove(_: Notification) {
        onDidMoveOrResize?()
    }

    func windowDidEndLiveResize(_: Notification) {
        onDidMoveOrResize?()
    }
}

// swiftlint:enable file_length
