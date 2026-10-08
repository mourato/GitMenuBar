//
//  StatusBarController.swift
//  GitMenuBar
//
//  Created by Gabriel on 12/28/24.
//

import AppKit
import Combine
import SwiftUI

// swiftlint:disable file_length
@MainActor
final class StatusBarController: NSObject {
    enum Constants {
        static let statusIconPointSize = NSSize(width: 18, height: 18)
        static let appFocusedShortcutIDs: [GlobalShortcutID] = [
            .commandPalette, .commit, .sync, .atomicCommits, .push, .branchManagement, .createBranch
        ]
    }

    var statusItem: NSStatusItem?
    private lazy var mainWindowController = MainWindowController(statusBarController: self)
    private lazy var appCommandRouter = AppCommandRouter(
        gitManager: gitManager,
        githubAuthManager: githubAuthManager,
        actionCoordinator: actionCoordinator,
        repositorySelectionCoordinator: repositorySelectionCoordinator,
        projectMonitor: projectMonitor,
        presentationModel: presentationModel,
        mainWindowController: { [mainWindowController] in mainWindowController },
        openMainWindow: { [weak self] in self?.openMainWindow() },
        openSettingsWindow: { [weak self] in self?.openSettingsWindow() },
        handleCommandPaletteShortcut: { [weak self] in self?.handleCommandPaletteShortcut() },
        presentMainWindowForActionFeedback: { [weak self] in self?.presentMainWindowForActionFeedback() },
        openMainWindowWithCreateRepo: { [weak self] in self?.openMainWindowWithCreateRepo(path: $0) },
        refreshAppCommands: { [weak self] in self?.refreshAppCommands() },
        openMainWindowForRoute: { [weak self] route, path, isGitRepo, shouldRefresh, trace in
            self?.openMainWindow(
                route: route,
                repositoryPath: path,
                isGitRepo: isGitRepo,
                shouldRefreshAfterPresentation: shouldRefresh,
                trace: trace
            )
        }
    )
    var contextMenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()
    var baseStatusImage: NSImage?
    private var remoteExistenceByPath: [String: RemoteExistenceState] = [:]
    private var shortcutQueue = MainWindowShortcutQueue()

    let dependencies: AppDependencies
    let gitManager: GitManager
    let loginItemManager: LoginItemManager
    let githubAuthManager: GitHubAuthManager
    let appCommandCenter: AppCommandCenter
    let aiProviderStore: AIProviderStore
    let aiKeychainStore: any AIAPIKeyStore
    let aiCommitMessageService: AICommitMessageService
    let shortcutActionBridge: MainMenuShortcutActionBridge
    let shortcutManager: GlobalShortcutManager
    let presentationModel: MainMenuPresentationModel
    let usageQuotaStore: UsageQuotaStore
    let usageQuotaPresentationPreferences: UsageQuotaPresentationPreferences
    let projectMonitor: ProjectMonitorStore
    let repositorySelectionCoordinator: RepositorySelectionCoordinator

    lazy var projectCleanupStore = dependencies.makeProjectCleanupStore { [weak self] paths in
        guard let self else { return }
        let selectedPath = repositorySelectionCoordinator.selectedPath
        guard !selectedPath.isEmpty,
              paths.contains(GitRepositoryContext.normalizedPath(selectedPath)) else { return }
        Task { await self.gitManager.refreshAsync(includeReflogHistory: false) }
    }

    lazy var aiCommitCoordinator = dependencies.makeAICommitCoordinator()
    lazy var actionCoordinator = dependencies.makeActionCoordinator(
        aiCommitCoordinator: aiCommitCoordinator,
        onCommitCompleted: { [weak self] path in
            self?.projectMonitor.refresh(path: path)
        }
    )
    lazy var commitHistoryEditCoordinator = dependencies.makeCommitHistoryEditCoordinator(
        aiCommitCoordinator: aiCommitCoordinator
    )
    private lazy var settingsWindowController = dependencies.makeSettingsWindowController(
        aiCommitCoordinator: aiCommitCoordinator,
        onSetAutoHideSuspended: { [weak self] suspended in
            self?.mainWindowController.setAutoHideSuspended(suspended)
        }
    )

    init(githubAuthManager: GitHubAuthManager, appCommandCenter: AppCommandCenter) {
        let dependencies = AppDependencies(
            githubAuthManager: githubAuthManager,
            appCommandCenter: appCommandCenter
        )
        self.dependencies = dependencies
        gitManager = dependencies.gitManager
        loginItemManager = dependencies.loginItemManager
        self.githubAuthManager = dependencies.githubAuthManager
        self.appCommandCenter = dependencies.appCommandCenter
        aiProviderStore = dependencies.aiProviderStore
        aiKeychainStore = dependencies.aiKeychainStore
        aiCommitMessageService = dependencies.aiCommitMessageService
        shortcutActionBridge = dependencies.shortcutActionBridge
        shortcutManager = dependencies.shortcutManager
        presentationModel = dependencies.presentationModel
        usageQuotaStore = dependencies.usageQuotaStore
        usageQuotaPresentationPreferences = dependencies.usageQuotaPresentationPreferences
        projectMonitor = dependencies.projectMonitor
        repositorySelectionCoordinator = dependencies.repositorySelectionCoordinator

        super.init()

        appCommandCenter.performInvocation = { [weak appCommandRouter] invocation in
            appCommandRouter?.performAppCommand(invocation)
        }

        if MainWindowPreferences.isShowMenuBarIconEnabled() {
            setupStatusItem()
        }
        setupVisibilityPreferencesObservation()
        setupShortcutHandlers()
        setupContextMenu()
        updateMainWindowToolbar()
        setupStatusItemObservation()
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
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        baseStatusImage = StatusItemBadgeRenderer.makeBaseStatusImage(iconSize: Constants.statusIconPointSize)

        guard let button = statusItem?.button else { return }
        button.image = baseStatusImage
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self

        updateStatusItemAppearance()
    }

    private func setupStatusItemObservation() {
        observeUsageQuotaForStatusItem()
    }

    private func observeUsageQuotaForStatusItem() {
        withObservationTracking {
            _ = usageQuotaStore.snapshots
            _ = usageQuotaStore.showAIUsageQuotas
            _ = usageQuotaStore.showClaudeCodeUsageQuota
            _ = usageQuotaStore.showCodexUsageQuota
            _ = usageQuotaStore.showCursorUsageQuota
            _ = usageQuotaStore.showOpenRouterUsageQuota
            _ = usageQuotaStore.showGeminiUsageQuota
            _ = usageQuotaStore.showAntigravityUsageQuota
            _ = usageQuotaPresentationPreferences.valueStyle
            _ = usageQuotaPresentationPreferences.meterStyle
            _ = usageQuotaPresentationPreferences.menuBarVisibility
            _ = usageQuotaPresentationPreferences.providerOrder
            for providerID in UsageProviderID.allCases {
                _ = usageQuotaPresentationPreferences.selectedMetrics(for: providerID)
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                updateStatusItemAppearance()
                observeUsageQuotaForStatusItem()
            }
        }
    }

    private func setupVisibilityPreferencesObservation() {
        NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.syncVisibilityPreferences()
        }
        .store(in: &cancellables)
    }

    private func syncVisibilityPreferences() {
        let showDock = MainWindowPreferences.isShowDockIconEnabled()
        let targetPolicy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
            if showDock {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        let showMenuBar = MainWindowPreferences.isShowMenuBarIconEnabled()
        if showMenuBar, statusItem == nil {
            setupStatusItem()
        } else if !showMenuBar, let currentItem = statusItem {
            NSStatusBar.system.removeStatusItem(currentItem)
            statusItem = nil
        }
    }

    private func setupShortcutHandlers() {
        let enabledIDs: Set<GlobalShortcutID> = NSApp.isActive
            ? Set(GlobalShortcutID.allCases)
            : [.togglePopover]
        shortcutManager.configure([
            GlobalShortcutAction(id: .togglePopover) { [weak self] in
                self?.toggleMainWindowFromShortcut()
            },
            GlobalShortcutAction(id: .commandPalette) { [weak self] in
                self?.handleCommandPaletteShortcut()
            },
            GlobalShortcutAction(id: .commit) { [weak self] in
                self?.handleActionShortcut(.commit)
            },
            GlobalShortcutAction(id: .sync) { [weak self] in
                self?.handleActionShortcut(.sync)
            },
            GlobalShortcutAction(id: .atomicCommits) { [weak self] in
                self?.handleActionShortcut(.atomicCommits)
            },
            GlobalShortcutAction(id: .push) { [weak self] in
                self?.appCommandCenter.perform(.push)
            },
            GlobalShortcutAction(id: .branchManagement) { [weak self] in
                self?.appCommandCenter.perform(.branchManagement)
            },
            GlobalShortcutAction(id: .createBranch) { [weak self] in
                self?.appCommandCenter.perform(.createBranch)
            }
        ], enabledIDs: enabledIDs)

        setupActionShortcutScopeObservation()
    }

    private func setupActionShortcutScopeObservation() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.updateActionShortcutScope(isAppActive: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.updateActionShortcutScope(isAppActive: false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.shortcutManager.stop()
            }
            .store(in: &cancellables)

        updateActionShortcutScope(isAppActive: NSApp.isActive)
    }

    private func updateActionShortcutScope(isAppActive: Bool) {
        shortcutManager.setEnabled(isAppActive, for: Constants.appFocusedShortcutIDs)
    }

    private func setupAuthenticationObservation() {
        mainWindowController.setAutoHideSuspended(githubAuthManager.isAuthenticating)
        observeAuthenticatingState()
    }

    private func observeAuthenticatingState() {
        withObservationTracking {
            _ = githubAuthManager.isAuthenticating
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                mainWindowController.setAutoHideSuspended(githubAuthManager.isAuthenticating)
                observeAuthenticatingState()
            }
        }
    }

    private func setupAppCommandObservation() {
        NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .receive(on: RunLoop.main)
        .map { _ in () }
        .sink { [weak self] in
            self?.refreshAppCommands()
            self?.updateMainWindowToolbar()
        }
        .store(in: &cancellables)

        observePresentationRoute()
        observeGitCommandState()
    }

    private func observePresentationRoute() {
        withObservationTracking {
            _ = presentationModel.route
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshAppCommands()
                updateMainWindowToolbar()
                observePresentationRoute()
            }
        }
    }

    private func observeGitCommandState() {
        withObservationTracking {
            _ = gitManager.stagedFiles
            _ = gitManager.changedFiles
            _ = gitManager.isAheadOfRemote
            _ = gitManager.isRemoteAhead
            _ = gitManager.remoteUrl
            _ = gitManager.currentBranch
            _ = gitManager.defaultBranchName
            _ = gitManager.isBehindRemote
            _ = githubAuthManager.isAuthenticated
            _ = projectMonitor.snapshots
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshAppCommands()
                updateMainWindowToolbar()
                observeGitCommandState()
            }
        }
    }

    private func setupContextMenu() {
        contextMenu = NSMenu()
        rebuildContextMenu()
    }

    private func updateMainWindowToolbar() {
        let shouldShowSidebarItem = switch presentationModel.route {
        case .createRepo:
            false
        case .main, .projectCleanup:
            true
        }
        let needsBackItem = switch presentationModel.route {
        case .projectCleanup:
            true
        case .main, .createRepo:
            false
        }
        mainWindowController.updateToolbar(
            title: mainWindowTitle,
            showsSidebarItem: shouldShowSidebarItem,
            showsBackItem: needsBackItem
        )
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

    /// Returns from a route-specific toolbar surface to the main repository view.
    @objc
    func goBackFromToolbar(_: NSToolbarItem) {
        presentationModel.showMain()
    }

    private func handleActionShortcut(_ action: MainMenuShortcutAction) {
        shortcutQueue.enqueue(action)

        if mainWindowController.isMainWindowVisible, presentationModel.route == .main {
            flushPendingShortcutActionsIfReady()
            return
        }

        let trace = mainWindowController.beginWindowOpenTrace(trigger: "shortcut_\(describe(shortcutAction: action))")
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
        if mainWindowController.isMainWindowVisible {
            presentationModel.showMain(requestCommitFocus: false)
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController.focus()
            Task { @MainActor [weak self] in
                self?.presentationModel.requestCommandPalettePresentation()
            }
            return
        }

        let trace = mainWindowController.beginWindowOpenTrace(trigger: "shortcut_commandPalette")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false

        openMainWindow(
            route: .main,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: true,
            trace: trace
        )
        Task { @MainActor [weak self] in
            self?.presentationModel.requestCommandPalettePresentation()
        }
    }

    private func flushPendingShortcutActionsIfReady() {
        let actions = shortcutQueue.dequeueAllIfReady(
            isWindowVisible: mainWindowController.isMainWindowVisible,
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

        if usageQuotaStore.showAIUsageQuotas {
            usageQuotaStore.refresh(reason: .manual)
        }
        rebuildContextMenu()
        statusItem?.menu = contextMenu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func toggleMainWindowFromShortcut() {
        let placementStrategy: MainWindowController.WindowPlacementStrategy = MainWindowPreferences
            .isToggleShortcutUsingMouseMonitorEnabled()
            ? .mousePointerMonitor
            : .statusItemAnchor

        toggleMainWindow(placementStrategy: placementStrategy)
    }

    @objc func toggleMainWindow(_: AnyObject?) {
        toggleMainWindow(placementStrategy: .statusItemAnchor)
    }

    private func toggleMainWindow(placementStrategy: MainWindowController.WindowPlacementStrategy) {
        if mainWindowController.isMainWindowVisible {
            mainWindowController.toggleVisibleWindow()
            return
        }

        let trace = mainWindowController.beginWindowOpenTrace(trigger: "toggle")
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
        trace: MainWindowController.WindowOpenTrace,
        placementStrategy: MainWindowController.WindowPlacementStrategy = .statusItemAnchor
    ) {
        presentationModel.prepareForPresentation(route: route, requestCommitFocus: route == .main)
        if route != .main {
            presentationModel.clearCreateRepoSuggestion()
        }

        mainWindowController.logWindowOpen(trace, message: "route resolved to \(describe(route: route))")
        mainWindowController.open(trace: trace, placementStrategy: placementStrategy)

        if shouldRefreshAfterPresentation {
            refreshMainWindowData(trace: trace)
        } else {
            presentationModel.finishRefresh()
            flushPendingShortcutActionsIfReady()
        }

        validateRemoteIfNeeded(path: repositoryPath, isGitRepo: isGitRepo, trace: trace)
    }

    private func openSettingsWindow() {
        settingsWindowController.show()
    }

    func showSettingsWindow() {
        openSettingsWindow()
    }

    /// Opens the main window programmatically (used when app is launched with a folder path)
    func openMainWindow() {
        if mainWindowController.isMainWindowVisible {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController.focus()
            return
        }

        let trace = mainWindowController.beginWindowOpenTrace(trigger: "programmatic")
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
        if mainWindowController.isMainWindowVisible {
            presentationModel.showMain(requestCommitFocus: true)
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController.focus()
            flushPendingShortcutActionsIfReady()
            return
        }

        let trace = mainWindowController.beginWindowOpenTrace(trigger: "context_action")
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
        let trace = mainWindowController.beginWindowOpenTrace(trigger: "create_repo")
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

    private func refreshMainWindowData(trace: MainWindowController.WindowOpenTrace) {
        let refreshGeneration = presentationModel.startRefresh()
        mainWindowController.logWindowOpen(trace, message: "refresh started")

        gitManager.refreshSelectedRepository(
            fastCompletion: { [weak self] in
                self?.presentationModel.markFastPhaseReady(generation: refreshGeneration)
            },
            completion: { [weak self] in
                guard let self else { return }

                presentationModel.finishRefresh(generation: refreshGeneration)
                flushPendingShortcutActionsIfReady()
                mainWindowController.logWindowOpen(trace, message: "refresh completed")
            }
        )
    }

    private func validateRemoteIfNeeded(path: String?, isGitRepo: Bool, trace: MainWindowController.WindowOpenTrace) {
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
        mainWindowController.logWindowOpen(trace, message: "remote validation started")

        gitManager.remoteRepositoryExists(at: path) { [weak self] exists in
            guard let self else { return }

            remoteExistenceByPath[path] = exists ? .exists : .missing
            mainWindowController.logWindowOpen(trace, message: "remote validation completed (\(exists ? "exists" : "missing"))")

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
