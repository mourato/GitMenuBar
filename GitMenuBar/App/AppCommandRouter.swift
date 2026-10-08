import AppKit

@MainActor
final class AppCommandRouter {
    private let gitManager: GitManager
    private let githubAuthManager: GitHubAuthManager
    private let actionCoordinator: MainMenuActionCoordinator
    private let repositorySelectionCoordinator: RepositorySelectionCoordinator
    private let projectMonitor: ProjectMonitorStore
    private let presentationModel: MainMenuPresentationModel
    private let mainWindowController: () -> MainWindowController
    private let openMainWindow: () -> Void
    private let openSettingsWindow: () -> Void
    private let handleCommandPaletteShortcut: () -> Void
    private let presentMainWindowForActionFeedback: () -> Void
    private let openMainWindowWithCreateRepo: (String) -> Void
    private let refreshAppCommands: () -> Void
    private let openMainWindowForRoute: (MainMenuRoute, String?, Bool, Bool, MainWindowController.WindowOpenTrace) -> Void

    init(
        gitManager: GitManager,
        githubAuthManager: GitHubAuthManager,
        actionCoordinator: MainMenuActionCoordinator,
        repositorySelectionCoordinator: RepositorySelectionCoordinator,
        projectMonitor: ProjectMonitorStore,
        presentationModel: MainMenuPresentationModel,
        mainWindowController: @escaping () -> MainWindowController,
        openMainWindow: @escaping () -> Void,
        openSettingsWindow: @escaping () -> Void,
        handleCommandPaletteShortcut: @escaping () -> Void,
        presentMainWindowForActionFeedback: @escaping () -> Void,
        openMainWindowWithCreateRepo: @escaping (String) -> Void,
        refreshAppCommands: @escaping () -> Void,
        openMainWindowForRoute: @escaping (MainMenuRoute, String?, Bool, Bool, MainWindowController.WindowOpenTrace) -> Void
    ) {
        self.gitManager = gitManager
        self.githubAuthManager = githubAuthManager
        self.actionCoordinator = actionCoordinator
        self.repositorySelectionCoordinator = repositorySelectionCoordinator
        self.projectMonitor = projectMonitor
        self.presentationModel = presentationModel
        self.mainWindowController = mainWindowController
        self.openMainWindow = openMainWindow
        self.openSettingsWindow = openSettingsWindow
        self.handleCommandPaletteShortcut = handleCommandPaletteShortcut
        self.presentMainWindowForActionFeedback = presentMainWindowForActionFeedback
        self.openMainWindowWithCreateRepo = openMainWindowWithCreateRepo
        self.refreshAppCommands = refreshAppCommands
        self.openMainWindowForRoute = openMainWindowForRoute
    }

    func performAppCommand(_ invocation: AppCommandInvocation) {
        switch invocation {
        case let .command(commandID):
            performAppCommand(commandID)
        case let .recentProject(path):
            selectRepository(path)
        }
    }

    func performAppCommand(_ commandID: AppCommandID) {
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
        mainWindowController().setAutoHideSuspended(true)
        DirectoryPickerService().selectDirectory(activateApp: true) { [weak self] selectedPath in
            guard let self else { return }
            mainWindowController().setAutoHideSuspended(false)

            guard let selectedPath else { return }
            selectRepository(selectedPath)
        }
    }

    private func selectRepository(_ path: String) {
        guard actionCoordinator.canSwitchRepository(to: path) else { return }

        let wasVisible = mainWindowController().isMainWindowVisible
        let result = repositorySelectionCoordinator.select(
            path: path,
            allowsNonGitSelection: !githubAuthManager.isAuthenticated
        )
        refreshAppCommands()

        guard case .selected = result else {
            if case let .requiresRepositoryCreation(candidatePath) = result {
                openMainWindowWithCreateRepo(candidatePath)
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
        if mainWindowController().isMainWindowVisible {
            presentationModel.showMain(requestCommitFocus: false)
            presentationModel.requestRepositoryOptionsPresentation()
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController().focus()
            return
        }

        let trace = mainWindowController().beginWindowOpenTrace(trigger: "repository_options")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false
        openMainWindowForRoute(.main, repositoryPath, isGitRepo, true, trace)
        Task { @MainActor [weak self] in
            self?.presentationModel.requestRepositoryOptionsPresentation()
        }
    }

    private func open(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func currentRepositoryPath() -> String? {
        let path = repositorySelectionCoordinator.selectedPath
        return path.isEmpty ? nil : path
    }
}
