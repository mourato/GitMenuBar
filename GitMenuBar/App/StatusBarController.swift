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
        actionCoordinator: actionCoordinator,
        repositorySelectionCoordinator: repositorySelectionCoordinator,
        projectMonitor: projectMonitor,
        presentationModel: presentationModel,
        mainWindowController: { [mainWindowController] in mainWindowController },
        openMainWindow: { [weak self] in self?.openMainWindow() },
        openSettingsWindow: { [weak self] in self?.openSettingsWindow() },
        handleCommandPaletteShortcut: { [weak self] in self?.handleCommandPaletteShortcut() },
        presentMainWindowForActionFeedback: { [weak self] in self?.presentMainWindowForActionFeedback() },
        refreshAppCommands: { [weak self] in self?.refreshAppCommands() }
    )
    var contextMenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()
    private var autoFetchTimer: Timer?
    private var lastAutoFetchEnabled = AppPreferences.isAutoFetchEnabled
    var baseStatusImage: NSImage?
    private var shortcutQueue = MainWindowShortcutQueue()

    let dependencies: AppDependencies
    let gitManager: GitManager
    let loginItemManager: LoginItemManager
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
        onFetchNow: { [weak self] in self?.fetchAllNow() }
    )

    init(appCommandCenter: AppCommandCenter) {
        let dependencies = AppDependencies(
            appCommandCenter: appCommandCenter
        )
        self.dependencies = dependencies
        gitManager = dependencies.gitManager
        loginItemManager = dependencies.loginItemManager
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
            _ = usageQuotaStore.showOpenCodeGoUsageQuota
            _ = usageQuotaPresentationPreferences.valueStyle
            _ = usageQuotaPresentationPreferences.meterStyle
            _ = usageQuotaPresentationPreferences.showsPace
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
            self?.fetchImmediatelyIfAutoFetchJustEnabled()
        }
        .store(in: &cancellables)

        observePresentationRoute()
        observeGitCommandState()
        startAutoFetchTimer()
    }

    private func startAutoFetchTimer() {
        autoFetchTimer?.invalidate()
        autoFetchTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      AppPreferences.isAutoFetchEnabled,
                      presentationModel.route == .main,
                      let path = currentRepositoryPath(), !path.isEmpty,
                      !actionCoordinator.isBusy
                else { return }
                _ = await actionCoordinator.refreshRemoteStatus()
            }
        }
    }

    func fetchAllNow() {
        projectMonitor.fetchAll()
        Task { @MainActor [weak self] in
            guard let self,
                  presentationModel.route == .main,
                  let path = currentRepositoryPath(), !path.isEmpty,
                  !actionCoordinator.isBusy
            else { return }
            _ = await actionCoordinator.refreshRemoteStatus()
        }
    }

    private func fetchImmediatelyIfAutoFetchJustEnabled() {
        let enabled = AppPreferences.isAutoFetchEnabled
        defer { lastAutoFetchEnabled = enabled }
        guard enabled, !lastAutoFetchEnabled else { return }
        fetchAllNow()
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
            _ = gitManager.commitCount
            _ = gitManager.behindCount
            _ = gitManager.remoteUrl
            _ = gitManager.currentBranch
            _ = gitManager.defaultBranchName
            _ = gitManager.isBehindRemote
            _ = projectMonitor.snapshots
            _ = repositorySelectionCoordinator.selectedPath
            _ = actionCoordinator.isBusy
            _ = actionCoordinator.operationStatus
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
        let shouldShowSidebarItem = presentationModel.route != .projectCleanup
        let needsBackItem = presentationModel.route == .projectCleanup
        let repositoryState: MainWindowToolbarRepositoryState?
        if MainWindowToolbarRepositoryState.isAvailable(
            isMainRoute: presentationModel.route == .main,
            repositoryPath: currentRepositoryPath(),
            isGitRepository: gitManager.isGitRepository(at:)
        ) {
            let operationStatus = actionCoordinator.operationStatus
            repositoryState = MainWindowToolbarRepositoryState(
                repositoryName: mainWindowTitle,
                branchName: gitManager.currentBranch,
                aheadCount: gitManager.isAheadOfRemote ? gitManager.commitCount : 0,
                behindCount: gitManager.isRemoteAhead ? gitManager.behindCount : 0,
                changeCount: gitManager.stagedFiles.count + gitManager.changedFiles.count,
                isBusy: actionCoordinator.isBusy,
                busyItem: actionCoordinator.isBusy ? toolbarBusyItem(for: operationStatus) : nil,
                progressAccessibilityLabel: operationStatus?.accessibilityLabel,
                autoFetchEnabled: AppPreferences.isAutoFetchEnabled
            )
        } else {
            repositoryState = nil
        }
        mainWindowController.updateToolbar(
            title: mainWindowTitle,
            showsSidebarItem: shouldShowSidebarItem,
            showsBackItem: needsBackItem,
            repositoryState: repositoryState
        )
    }

    private func toolbarBusyItem(
        for operationStatus: MainMenuOperationStatus?
    ) -> MainWindowToolbarRepositoryItem? {
        switch operationStatus {
        case .fetching:
            .fetch
        case .pushing, .pushingCommits:
            .sync
        case .generatingCommitMessage, .groupingChanges, .committing, .committingGroup, nil:
            nil
        }
    }

    private var mainWindowTitle: String {
        switch presentationModel.route {
        case .main:
            guard let path = currentRepositoryPath() else { return "GitMenuBar" }
            let normalizedPath = RecentProjectsStore.normalize(path)
            return RecentProjectsStore().recentProjects().first { $0.path == normalizedPath }?.name
                ?? PathDisplayFormatter.defaultProjectName(for: path)
        case .projectCleanup:
            return "Project Cleanup"
        }
    }

    @objc
    func goBackFromToolbar(_: NSToolbarItem) {
        presentationModel.showMain()
    }

    @objc
    func presentBranchSelectorFromToolbar(_: Any?) {
        shortcutActionBridge.send(.branchSelector)
    }

    @objc
    func performFetchFromToolbar(_: Any?) {
        shortcutActionBridge.send(.fetch)
    }

    @objc
    func performSyncFromToolbar(_: Any?) {
        shortcutActionBridge.send(.sync)
    }

    private func handleActionShortcut(_ action: MainMenuShortcutAction) {
        shortcutQueue.enqueue(action)

        if mainWindowController.isMainWindowVisible, presentationModel.route == .main {
            flushPendingShortcutActionsIfReady()
            return
        }

        let trace = mainWindowController.beginWindowOpenTrace(trigger: "shortcut_\(describe(shortcutAction: action))")
        openMainWindow(
            route: .main,
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
        openMainWindow(
            route: .main,
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
        openMainWindow(
            route: .main,
            shouldRefreshAfterPresentation: true,
            trace: trace,
            placementStrategy: placementStrategy
        )
    }

    private func openMainWindow(
        route: MainMenuRoute,
        shouldRefreshAfterPresentation: Bool,
        trace: MainWindowController.WindowOpenTrace,
        placementStrategy: MainWindowController.WindowPlacementStrategy = .statusItemAnchor
    ) {
        presentationModel.prepareForPresentation(route: route, requestCommitFocus: route == .main)

        mainWindowController.logWindowOpen(trace, message: "route resolved to \(describe(route: route))")
        mainWindowController.open(trace: trace, placementStrategy: placementStrategy)

        if shouldRefreshAfterPresentation {
            refreshMainWindowData(trace: trace)
        } else {
            presentationModel.finishRefresh()
            flushPendingShortcutActionsIfReady()
        }
    }

    private func openSettingsWindow() {
        settingsWindowController.show()
    }

    func showSettingsWindow() {
        openSettingsWindow()
    }

    func openMainWindow() {
        if mainWindowController.isMainWindowVisible {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController.focus()
            return
        }

        let trace = mainWindowController.beginWindowOpenTrace(trigger: "programmatic")
        openMainWindow(
            route: .main,
            shouldRefreshAfterPresentation: true,
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
        openMainWindow(
            route: .main,
            shouldRefreshAfterPresentation: true,
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
                hasWorkingTreeChanges: hasWorkingTreeChanges,
                canDoAtomicCommits: hasWorkingTreeChanges && aiCommitCoordinator.isReadyForGeneration,
                isBehindRemote: gitManager.isBehindRemote,
                isAheadOfRemote: gitManager.isAheadOfRemote,
                canShowBranchManagement: !(currentRepositoryPath()?.isEmpty ?? true),
                currentBranch: gitManager.currentBranch,
                defaultBranchName: gitManager.defaultBranchName,
                monitoredProjects: Array(projectMonitor.snapshots.values),
                canSyncAll: projectMonitor.snapshots.values.contains(where: ProjectMonitorStore.isSafeToFastForward)
            )
        )

        appCommandCenter.apply(snapshot)
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

    private func describe(route: MainMenuRoute) -> String {
        switch route {
        case .main:
            "main"
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
        case .fetch:
            "fetch"
        case .branchSelector:
            "branchSelector"
        }
    }
}
