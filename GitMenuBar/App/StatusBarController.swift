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
final class StatusBarController: NSObject, ObservableObject {
    private enum Constants {
        static let statusIconPointSize = NSSize(width: 16, height: 16)
        static let windowInitialSize = NSSize(width: WorkbenchMetrics.mainWindowInitialWidth, height: 720)
        static let windowMinimumHeight: CGFloat = 640
        static let windowMinimumSize = NSSize(width: WorkbenchMetrics.mainWindowMinimumWidth, height: windowMinimumHeight)
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

    var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var mainWindowToolbarDelegate: MainWindowToolbarDelegate?
    var contextMenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()
    private var baseStatusImage: NSImage?
    private var remoteExistenceByPath: [String: RemoteExistenceState] = [:]
    private var nextWindowOpenTraceID = 0
    private var hasPositionedWindowInitially = false
    private var isAutoHideSuspended = false
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
    let repositorySelectionCoordinator: RepositorySelectionCoordinator
    lazy var projectCleanupStore = ProjectCleanupStore(
        projectMonitor: projectMonitor,
        onAffectedPaths: { [weak self] paths in
            guard let self else { return }
            let selectedPath = repositorySelectionCoordinator.selectedPath
            guard !selectedPath.isEmpty,
                  paths.contains(GitRepositoryContext.normalizedPath(selectedPath)) else { return }
            gitManager.refresh(includeReflogHistory: false)
        }
    )

    lazy var aiCommitCoordinator = AICommitCoordinator(
        providerStore: aiProviderStore,
        keychainStore: aiKeychainStore,
        messageService: aiCommitMessageService,
        gitManager: gitManager
    )
    lazy var actionCoordinator = MainMenuActionCoordinator(
        gitManager: gitManager,
        aiCommitCoordinator: aiCommitCoordinator,
        onCommitCompleted: { [weak self] path in
            self?.projectMonitor.refresh(path: path)
        }
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
            aiKeychainStore = cachedStore
        }
        usageQuotaStore = UsageQuotaStore(providers: [CodexUsageProvider(), CursorUsageProvider(), OpenRouterUsageProvider(keyStore: aiKeychainStore)])
        repositorySelectionCoordinator = RepositorySelectionCoordinator(
            gitManager: gitManager,
            projectMonitor: projectMonitor
        )

        super.init()

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
        setupShortcutHandlers()
        setupContextMenu()
        setupMainWindow()
        setupBadgeObservation()
        setupAuthenticationObservation()
        setupAppCommandObservation()

        Task { @MainActor [weak self] in
            await self?.projectMonitor.seed(
                currentPath: self?.repositorySelectionCoordinator.selectedPath ?? "",
                recentProjects: RecentProjectsStore().recentProjects()
            )
        }
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
            .receive(on: RunLoop.main)
            .map { _ in () }
            .eraseToAnyPublisher()
        ]

        Publishers.MergeMany(publishers)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.refreshAppCommands()
                self?.updateMainWindowToolbar()
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
        configureMainWindowToolbar(window)
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
        updateMainWindowToolbar()
    }

    private func configureMainWindowAppearance(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.hasShadow = true
        window.isMovableByWindowBackground = false
    }

    private func configureMainWindowToolbar(_ window: NSWindow) {
        let toolbar = NSToolbar(identifier: "GitMenuBar.MainWindowToolbar")
        let toolbarDelegate = MainWindowToolbarDelegate(target: self)
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        mainWindowToolbarDelegate = toolbarDelegate
    }

    fileprivate func makeMainWindowToolbarItem(
        identifier: NSToolbarItem.Identifier
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self

        switch identifier {
        case MainWindowToolbarItemIdentifier.sidebarToggle:
            item.label = "Projects"
            item.paletteLabel = "Projects"
            item.toolTip = "Show or hide Projects sidebar"
            item.action = #selector(toggleProjectsSidebarFromToolbar(_:))
            item.image = toolbarSidebarImage()
        case MainWindowToolbarItemIdentifier.back:
            item.label = "Back"
            item.paletteLabel = "Back"
            item.toolTip = "Return to the main repository view"
            item.action = #selector(goBackFromToolbar(_:))
            item.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back")
        case MainWindowToolbarItemIdentifier.title:
            let titleField = NSTextField(labelWithString: mainWindowTitle)
            titleField.alignment = .center
            titleField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            titleField.lineBreakMode = .byTruncatingTail
            titleField.maximumNumberOfLines = 1
            titleField.translatesAutoresizingMaskIntoConstraints = false
            item.view = titleField
            NSLayoutConstraint.activate([
                titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
                titleField.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
                titleField.heightAnchor.constraint(equalToConstant: 22)
            ])
        default:
            return nil
        }

        return item
    }

    private func updateMainWindowToolbar() {
        guard let window = mainWindow, let toolbar = window.toolbar else { return }

        window.title = mainWindowTitle

        let titleField = toolbar.items
            .first(where: { $0.itemIdentifier == MainWindowToolbarItemIdentifier.title })?.view as? NSTextField
        if let titleField {
            titleField.stringValue = mainWindowTitle
        }

        let shouldShowSidebarItem = if case .createRepo = presentationModel.route {
            false
        } else {
            true
        }
        let hasSidebarItem = toolbar.items.contains { $0.itemIdentifier == MainWindowToolbarItemIdentifier.sidebarToggle }
        if shouldShowSidebarItem, !hasSidebarItem {
            toolbar.insertItem(withItemIdentifier: MainWindowToolbarItemIdentifier.sidebarToggle, at: 0)
        } else if !shouldShowSidebarItem, let sidebarIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == MainWindowToolbarItemIdentifier.sidebarToggle }) {
            toolbar.removeItem(at: sidebarIndex)
        }

        if let sidebarItem = toolbar.items.first(where: { $0.itemIdentifier == MainWindowToolbarItemIdentifier.sidebarToggle }) {
            sidebarItem.image = toolbarSidebarImage()
            sidebarItem.toolTip = isProjectsSidebarCollapsed ? "Show Projects sidebar" : "Hide Projects sidebar"
        }

        let needsBackItem = switch presentationModel.route {
        case .projectCleanup:
            true
        case .main, .createRepo:
            false
        }
        let hasBackItem = toolbar.items.contains { $0.itemIdentifier == MainWindowToolbarItemIdentifier.back }
        if needsBackItem, !hasBackItem {
            toolbar.insertItem(withItemIdentifier: MainWindowToolbarItemIdentifier.back, at: 1)
        } else if !needsBackItem, let backIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == MainWindowToolbarItemIdentifier.back }) {
            toolbar.removeItem(at: backIndex)
        }
    }

    private var mainWindowTitle: String {
        switch presentationModel.route {
        case .main:
            guard let path = currentRepositoryPath() else { return "GitMenuBar" }
            let normalizedPath = RecentProjectsStore.normalize(path)
            return RecentProjectsStore().recentProjects().first { $0.path == normalizedPath }?.name
                ?? PathDisplayFormatter.defaultProjectName(for: path)
        case .createRepo:
            return "Create Repository"
        case .projectCleanup:
            return "Project Cleanup"
        }
    }

    private var isProjectsSidebarCollapsed: Bool {
        UserDefaults.standard.bool(forKey: AppPreferences.Keys.isProjectsSidebarCollapsed)
    }

    private func toolbarSidebarImage() -> NSImage? {
        NSImage(
            systemSymbolName: isProjectsSidebarCollapsed ? "sidebar.right" : "sidebar.left",
            accessibilityDescription: isProjectsSidebarCollapsed ? "Show Projects sidebar" : "Hide Projects sidebar"
        )
    }

    @objc
    private func toggleProjectsSidebarFromToolbar(_: NSToolbarItem) {
        if case .createRepo = presentationModel.route {
            return
        }
        let key = AppPreferences.Keys.isProjectsSidebarCollapsed
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }

    @objc
    private func goBackFromToolbar(_: NSToolbarItem) {
        presentationModel.showMain()
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
        .environmentObject(repositorySelectionCoordinator)
        .environmentObject(projectCleanupStore)

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
        mainWindow?.isVisible == true
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
            if NSApp.isActive, mainWindow?.isKeyWindow == true {
                hideMainWindow()
            } else {
                NSApp.activate(ignoringOtherApps: true)
                mainWindow?.makeKeyAndOrderFront(nil)
            }
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

        if mainWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            refreshUsageQuotaOnWindowPresented()
            return
        }

        if restoreMainWindowFrameIfAvailable(mainWindow) {
            normalizeMainWindowSize(mainWindow)
            if let screen = mainWindow.screen ?? NSScreen.main {
                fitMainWindowWidthToVisibleFrame(mainWindow, visibleFrame: screen.visibleFrame)
                clampMainWindowOriginToVisibleFrame(mainWindow, visibleFrame: screen.visibleFrame)
            }
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

        mainWindow.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
        logWindowOpen(trace, message: "window visible")
        refreshUsageQuotaOnWindowPresented()
    }

    private func refreshUsageQuotaOnWindowPresented() {
        usageQuotaStore.refresh(reason: .windowPresented)
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

        fitMainWindowWidthToVisibleFrame(window, visibleFrame: visibleFrame)

        var originX = buttonRectInScreen.maxX - window.frame.width
        var originY = buttonRectInScreen.minY - window.frame.height - 8

        let minX = visibleFrame.minX + 8
        let maxX = max(minX, visibleFrame.maxX - window.frame.width - 8)
        originX = min(max(originX, minX), maxX)

        let minY = visibleFrame.minY + 8
        let maxY = max(minY, visibleFrame.maxY - window.frame.height - 20)

        if originY < minY {
            originY = maxY
        }
        originY = min(max(originY, minY), maxY)

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

        fitMainWindowWidthToVisibleFrame(window, visibleFrame: visibleFrame)

        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - window.frame.width - margin)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - window.frame.height - margin)

        let originX = max(minX, maxX)
        let originY = max(minY, maxY)

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func fitMainWindowWidthToVisibleFrame(_ window: NSWindow, visibleFrame: NSRect) {
        let margin: CGFloat = 8
        let maxFrameWidth = visibleFrame.width - (margin * 2)
        guard maxFrameWidth > 0, window.frame.width > maxFrameWidth else { return }

        let currentContentSize = window.contentRect(forFrameRect: window.frame).size
        let frameChromeWidth = window.frame.width - currentContentSize.width
        let maxContentWidth = maxFrameWidth - frameChromeWidth
        guard maxContentWidth >= window.contentMinSize.width else { return }

        window.setContentSize(
            NSSize(width: maxContentWidth, height: currentContentSize.height)
        )
    }

    private func clampMainWindowOriginToVisibleFrame(_ window: NSWindow, visibleFrame: NSRect) {
        let margin: CGFloat = 8
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - window.frame.width - margin)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - window.frame.height - margin)
        let originX = min(max(window.frame.minX, minX), maxX)
        let originY = min(max(window.frame.minY, minY), maxY)

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
        guard let mainWindow, mainWindow.isVisible else { return }

        persistMainWindowFrame(mainWindow)
        mainWindow.orderOut(nil)
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
        let path = repositorySelectionCoordinator.selectedPath
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
        guard actionCoordinator.canSwitchRepository(to: path) else { return }

        let wasVisible = isMainWindowVisible
        let result = repositorySelectionCoordinator.select(
            path: path,
            allowsNonGitSelection: !githubAuthManager.isAuthenticated
        )
        refreshAppCommands()

        guard case .selected = result else {
            if case let .requiresRepositoryCreation(candidatePath) = result {
                openMainWindowWithCreateRepo(path: candidatePath)
            }
            return
        }

        actionCoordinator.resetForRepositorySwitch()
        openMainWindow()
        guard wasVisible else { return }

        let refreshGeneration = presentationModel.startRefresh()
        gitManager.refreshSelectedRepository(
            includeReflogHistory: false,
            fastCompletion: { [weak self] in
                self?.presentationModel.markFastPhaseReady(generation: refreshGeneration)
            },
            completion: { [weak self] in
                self?.presentationModel.finishRefresh(generation: refreshGeneration)
            }
        )
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
        let refreshGeneration = presentationModel.startRefresh()
        logWindowOpen(trace, message: "refresh started")

        gitManager.refreshSelectedRepository(
            fastCompletion: { [weak self] in
                self?.presentationModel.markFastPhaseReady(generation: refreshGeneration)
            },
            completion: { [weak self] in
                guard let self else { return }

                presentationModel.finishRefresh(generation: refreshGeneration)
                flushPendingShortcutActionsIfReady()
                logWindowOpen(trace, message: "refresh completed")
            }
        )
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

            guard let currentPath = currentRepositoryPath(),
                  RecentProjectsStore.normalize(currentPath) == RecentProjectsStore.normalize(path) else { return }

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
        case .projectCleanup:
            "projectCleanup"
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

private enum MainWindowToolbarItemIdentifier {
    static let sidebarToggle = NSToolbarItem.Identifier("GitMenuBar.sidebarToggle")
    static let back = NSToolbarItem.Identifier("GitMenuBar.back")
    static let title = NSToolbarItem.Identifier("GitMenuBar.title")
}

@MainActor
private final class MainWindowToolbarDelegate: NSObject, NSToolbarDelegate {
    private weak var target: StatusBarController?

    init(target: StatusBarController) {
        self.target = target
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            MainWindowToolbarItemIdentifier.sidebarToggle,
            MainWindowToolbarItemIdentifier.back,
            .flexibleSpace,
            MainWindowToolbarItemIdentifier.title
        ]
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            MainWindowToolbarItemIdentifier.sidebarToggle,
            .flexibleSpace,
            MainWindowToolbarItemIdentifier.title,
            .flexibleSpace
        ]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        target?.makeMainWindowToolbarItem(identifier: itemIdentifier)
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
