//
//  StatusBarController.swift
//  GitMenuBar
//

import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

// swiftlint:disable file_length type_body_length
@MainActor
final class StatusBarController: ObservableObject {
    private enum Constants {
        static let statusIconPointSize = NSSize(width: 16, height: 16)
        static let windowInitialSize = NSSize(width: 400, height: 700)
        static let windowMinimumSize = NSSize(width: 360, height: 620)
        static let windowAutosaveName = NSWindow.FrameAutosaveName("GitMenuBar.MainWindow")
        static let appFocusedShortcutNames: [KeyboardShortcuts.Name] = [.commandPalette, .commit, .sync]
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

    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var contextMenu: NSMenu?
    private var badgeRefreshTimer: Timer?
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
        onSetAutoHideSuspended: { [weak self] suspended in
            self?.setAutoHideSuspended(suspended)
        },
        onRequestCreateRepo: { [weak self] path in
            self?.openMainWindowWithCreateRepo(path: path)
        }
    )

    init(githubAuthManager: GitHubAuthManager, appCommandCenter: AppCommandCenter) {
        self.githubAuthManager = githubAuthManager
        self.appCommandCenter = appCommandCenter
        if AppExecutionContext.usesEphemeralCredentialStores {
            aiKeychainStore = InMemoryAIAPIKeyStore()
        } else {
            let cachedStore = CachedAIAPIKeyStore(backingStore: AIKeychainStore())
            cachedStore.preloadAllKeys() // Eagerly load all keys to avoid multiple keychain prompts
            aiKeychainStore = cachedStore
        }

        // Wire up token provider for git push operations
        gitManager.tokenProvider = { [weak githubAuthManager] in
            githubAuthManager?.getStoredToken()
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
        setupBadgeRefreshTimer()
        setupShortcutHandlers()
        setupAuthenticationObservation()
        setupAppCommandObservation()

        gitManager.updateUncommittedFiles()
        refreshAppCommands()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 20)
        baseStatusImage = makeBaseStatusImage()

        guard let button = statusItem?.button else { return }
        button.image = baseStatusImage
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self

        updateStatusItemBadge(count: 0)
    }

    private func makeBaseStatusImage() -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon") {
            let resized = image.copy() as? NSImage ?? image
            resized.size = Constants.statusIconPointSize
            resized.isTemplate = true
            return resized
        }

        let fallback = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: "GitBar")
        fallback?.isTemplate = true
        return fallback
    }

    private func updateStatusItemBadge(count: Int) {
        guard let button = statusItem?.button else { return }

        guard count > 0 else {
            button.image = baseStatusImage
            return
        }

        button.image = makeBadgedImage(count: count)
    }

    private func makeBadgedImage(count: Int) -> NSImage? {
        guard let baseStatusImage else { return nil }

        let iconSize = Constants.statusIconPointSize
        let image = NSImage(size: iconSize)

        image.lockFocus()

        let iconRect = NSRect(x: 0, y: 0, width: iconSize.width, height: iconSize.height)
        baseStatusImage.draw(in: iconRect)

        let displayText = count > 99 ? "99+" : "\(count)"
        let badgeWidth: CGFloat = displayText.count >= 3 ? 17 : (displayText.count == 2 ? 14 : 12)
        let badgeRect = NSRect(x: iconSize.width - badgeWidth + 1, y: iconSize.height - 11, width: badgeWidth, height: 11)

        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 5.5, yRadius: 5.5).fill()

        let fontSize: CGFloat = displayText.count >= 3 ? 6 : 8
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = displayText.size(withAttributes: attributes)
        let textRect = NSRect(
            x: badgeRect.midX - (textSize.width / 2),
            y: badgeRect.midY - (textSize.height / 2),
            width: textSize.width,
            height: textSize.height
        )

        displayText.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func setupBadgeObservation() {
        gitManager.$uncommittedFiles
            .receive(on: RunLoop.main)
            .sink { [weak self] files in
                self?.updateStatusItemBadge(count: files.count)
            }
            .store(in: &cancellables)
    }

    private func setupBadgeRefreshTimer() {
        badgeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.gitManager.updateUncommittedFiles()
        }

        if let badgeRefreshTimer {
            RunLoop.main.add(badgeRefreshTimer, forMode: .common)
        }
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
        window.minSize = Constants.windowMinimumSize
        window.setFrameAutosaveName(Constants.windowAutosaveName)
        hasPositionedWindowInitially = window.setFrameUsingName(Constants.windowAutosaveName, force: false)

        let hostingController = NSHostingController(rootView: makeRootView())
        window.contentViewController = hostingController

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

        self.hostingController = hostingController
        mainWindow = window
    }

    private func configureMainWindowAppearance(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
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

        return AnyView(rootView)
    }

    private func setAutoHideSuspended(_ suspended: Bool) {
        isAutoHideSuspended = suspended
    }

    private func handleMainWindowDidResignKey() {
        guard shouldAutoHideOnBlur else { return }
        hideMainWindow()
    }

    private var shouldAutoHideOnBlur: Bool {
        MainWindowPreferences.isAutoHideOnBlurEnabled() && !isAutoHideSuspended
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

    private func rebuildContextMenu() {
        let menu = contextMenu ?? NSMenu()
        menu.removeAllItems()

        if appendCommandItems([.commit, .commitAndPush, .sync], to: menu) {
            menu.addItem(NSMenuItem.separator())
        }

        if appendCommandItems(
            [.openRepositoryOnGitHub, .revealRepositoryInFinder, .showRepositoryOptions],
            to: menu
        ) {
            menu.addItem(NSMenuItem.separator())
        }

        appendRecentProjectsMenu(to: menu)
        addCommandMenuItem(.chooseRepository, to: menu)
        menu.addItem(NSMenuItem.separator())

        addCommandMenuItem(.showSettings, to: menu)
        addCommandMenuItem(.quit, to: menu)

        contextMenu = menu
    }

    private func appendCommandItems(_ commandIDs: [AppCommandID], to menu: NSMenu) -> Bool {
        let hasEnabledItem = commandIDs.contains { appCommandCenter.state(for: $0).isEnabled }

        for commandID in commandIDs {
            addCommandMenuItem(commandID, to: menu)
        }

        return hasEnabledItem
    }

    private func addCommandMenuItem(_ commandID: AppCommandID, to menu: NSMenu) {
        let state = appCommandCenter.state(for: commandID)
        let item = makeMenuItem(
            title: state.title,
            action: #selector(handleContextMenuCommand(_:)),
            representedCommand: commandID,
            isEnabled: state.isEnabled
        )
        menu.addItem(item)
    }

    private func appendRecentProjectsMenu(to menu: NSMenu) {
        guard !appCommandCenter.recentProjects.isEmpty else {
            return
        }

        let recentMenuItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Open Recent")

        for project in appCommandCenter.recentProjects {
            let item = NSMenuItem(
                title: project.title,
                action: #selector(handleRecentProjectContextMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.toolTip = project.subtitle
            item.representedObject = project.path
            submenu.addItem(item)
        }

        recentMenuItem.submenu = submenu
        menu.addItem(recentMenuItem)
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        representedCommand: AppCommandID,
        isEnabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedCommand
        item.isEnabled = isEnabled
        return item
    }

    @objc private func handleContextMenuCommand(_ sender: NSMenuItem) {
        guard let commandID = sender.representedObject as? AppCommandID else {
            return
        }

        appCommandCenter.perform(commandID)
    }

    @objc private func handleRecentProjectContextMenuItem(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else {
            return
        }
        appCommandCenter.performRecentProject(path: path)
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

        if restoreMainWindowFrameIfAvailable(mainWindow) {
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

        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
        logWindowOpen(trace, message: "window shown")
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
        let path = UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
        return path.isEmpty ? nil : path
    }

    private func refreshAppCommands() {
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
                recentPaths: RecentProjectsStore().recentPaths(),
                isGitHubAuthenticated: githubAuthManager.isAuthenticated
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
            .revealRepositoryInFinder: revealCurrentRepositoryInFinder,
            .openRepositoryOnGitHub: openCurrentRepositoryOnGitHub,
            .showRepositoryOptions: presentRepositoryOptions,
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

    private func chooseRepository() {
        setAutoHideSuspended(true)
        DirectoryPickerService().selectDirectory(activateApp: true) { [weak self] selectedPath in
            guard let self else { return }
            self.setAutoHideSuspended(false)

            guard let selectedPath else { return }
            self.selectRepository(selectedPath)
        }
    }

    private func selectRepository(_ path: String) {
        UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
        RecentProjectsStore().add(path)
        refreshAppCommands()

        if !gitManager.isGitRepository(at: path), githubAuthManager.isAuthenticated {
            openMainWindowWithCreateRepo(path: path)
            return
        }

        openMainWindow()
        gitManager.refresh(includeReflogHistory: false)
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

        gitManager.updateUncommittedFiles { [weak self] in
            guard let self else { return }

            self.logWindowOpen(trace, message: "working tree loaded")
            self.gitManager.refresh {
                self.presentationModel.finishRefresh()
                self.flushPendingShortcutActionsIfReady()
                self.logWindowOpen(trace, message: "refresh completed")
            }
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

            self.remoteExistenceByPath[path] = exists ? .exists : .missing
            self.logWindowOpen(trace, message: "remote validation completed (\(exists ? "exists" : "missing"))")

            guard self.currentRepositoryPath() == path else { return }

            if exists {
                self.presentationModel.clearCreateRepoSuggestion()
                return
            }

            if self.presentationModel.route == .main {
                self.presentationModel.suggestCreateRepo(path: path)
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
            return "main"
        case let .createRepo(path):
            return "createRepo(\(path))"
        case let .historyDetail(commitID):
            return "historyDetail(\(commitID))"
        }
    }

    private func describe(shortcutAction: MainMenuShortcutAction) -> String {
        switch shortcutAction {
        case .commit:
            return "commit"
        case .sync:
            return "sync"
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

// swiftlint:enable file_length type_body_length
