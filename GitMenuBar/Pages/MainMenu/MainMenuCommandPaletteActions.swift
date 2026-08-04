//
//  MainMenuCommandPaletteActions.swift
//  GitMenuBar
//

import AppKit

extension MainMenuView {
    func executeCommandPaletteItem(_ item: MainMenuCommandPaletteItem) {
        switch MainMenuCommandPaletteResolver.executionDecision(for: item.kind) {
        case .executeNow:
            closeCommandPalette()
            executeCommandPaletteItemImmediately(item)
        case .requiresConfirmation:
            closeCommandPalette()
            showRestartConfirmation = true
        }
    }

    private func executeCommandPaletteItemImmediately(_ item: MainMenuCommandPaletteItem) {
        switch item.kind {
        case .commit, .commitAndPush, .sync, .push, .pull:
            executeRepositoryCommand(item.kind)
        case .atomicCommits, .branchManagement, .createBranch, .mergeToDefault, .switchToBranchList, .switchBranch:
            executeWorkflowCommand(item.kind)
        case let .recentProject(path):
            switchRepository(path: path)
        case .addProject:
            selectDirectory()
        case .refreshAllProjects:
            projectMonitor.refreshAll()
        case .fetchAllProjects:
            projectMonitor.fetchAll()
        case .restartApp:
            showRestartConfirmation = true
        case .quitApp:
            NSApplication.shared.terminate(nil)
        }
    }

    private func executeRepositoryCommand(_ kind: MainMenuCommandPaletteKind) {
        switch kind {
        case .commit:
            Task {
                _ = await actionCoordinator.performCommit(
                    commentText: "",
                    forceAutomaticMessage: true
                )
            }
        case .commitAndPush:
            Task {
                _ = await actionCoordinator.performCommit(
                    commentText: "",
                    forceAutomaticMessage: true,
                    shouldPushAfterCommit: true
                )
            }
        case .sync, .push:
            Task {
                _ = await actionCoordinator.performSync()
            }
        case .pull:
            Task {
                _ = await actionCoordinator.syncWithRemote(rebase: useRebase)
            }
        default:
            break
        }
    }

    private func executeWorkflowCommand(_ kind: MainMenuCommandPaletteKind) {
        switch kind {
        case .atomicCommits:
            startAtomicCommitFlow()
        case .branchManagement:
            showBranchManagement = true
        case .createBranch:
            showCreateBranch = true
        case let .mergeToDefault(featureBranch):
            Task {
                let detectedDefaultBranch = await gitManager.getDefaultBranchNameAsync()
                featureBranchName = featureBranch
                defaultBranchName = detectedDefaultBranch
                showMergeCleanupDialog = true
            }
        case .switchToBranchList:
            presentBranchSelector()
        case let .switchBranch(branchName):
            gitManager.switchBranch(branchName: branchName) { result in
                if case let .failure(error) = result {
                    branchSwitchError = error.localizedDescription
                }
            }
        default:
            break
        }
    }
}
