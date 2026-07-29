//
//  MainMenuActions.swift
//  GitMenuBar
//

import AppKit
import Foundation
import SwiftUI

extension MainMenuView {
    private var shouldRevealCommitFieldBeforeSubmitting: Bool {
        hideCommitMessageField && !isCommitFieldTemporarilyVisible && !aiCommitCoordinator.isReadyForGeneration
    }

    func submitComment() async {
        if shouldRevealCommitFieldBeforeSubmitting {
            revealCommitFieldForManualEntry()
            return
        }

        let result = await actionCoordinator.performCommit(commentText: commentText)
        if result.didCommit {
            HapticFeedback.actionSucceeded()
            commentText = ""
            if hideCommitMessageField {
                isCommitFieldTemporarilyVisible = false
            }
        }
    }

    func performPrimaryAction() async {
        if showsCommitAction {
            await submitComment()
            return
        }
        handleSyncResult(await actionCoordinator.performSync())
    }

    func syncRepository() {
        Task {
            handleSyncResult(await actionCoordinator.performSync())
        }
    }

    func syncWithRemote() {
        Task {
            handleSyncResult(await actionCoordinator.syncWithRemote(rebase: useRebase))
        }
    }

    private func handleSyncResult(_ result: MainMenuSyncExecutionResult) {
        if result == .synced {
            HapticFeedback.actionSucceeded()
        } else if result == .failed {
            HapticFeedback.actionFailed()
        }
    }

    func createNewBranch() {
        createBranchError = nil
        gitManager.createBranch(branchName: newBranchName) { result in
            switch result {
            case .success:
                showCreateBranch = false
                newBranchName = ""
            case let .failure(error):
                createBranchError = error.localizedDescription
            }
        }
    }

    func renameBranch() {
        renameBranchError = nil
        gitManager.renameBranch(oldName: oldBranchName, newName: renameBranchNewName) { result in
            switch result {
            case .success:
                showRenameBranch = false
                renameBranchNewName = ""
                oldBranchName = ""
            case let .failure(error):
                renameBranchError = error.localizedDescription
            }
        }
    }

    func pullToNewBranch() {
        let name = pullToNewBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        gitManager.pullToNewBranch(newBranchName: name) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showPullToNewBranch = false
                    pullToNewBranchName = ""
                case let .failure(error):
                    syncError = error.localizedDescription
                }
            }
        }
    }

    func stageFile(path: String) {
        gitManager.stageFile(path: path) { handleFileActionResult($0) }
    }

    func stageAllFiles() {
        gitManager.stageAllChanges { handleFileActionResult($0) }
    }

    func unstageFile(path: String) {
        gitManager.unstageFile(path: path) { handleFileActionResult($0) }
    }

    func unstageAllFiles() {
        gitManager.unstageAllChanges { handleFileActionResult($0) }
    }

    private func handleFileActionResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            HapticFeedback.actionSucceeded()
        case let .failure(error):
            syncError = error.localizedDescription
        }
    }

    func switchRepository(path: String) {
        if !gitManager.isGitRepository(at: path), githubAuthManager.isAuthenticated {
            presentationModel.showCreateRepo(path: path)
            return
        }

        setCurrentRepositoryPath(path)
        addToRecents(path)
        gitManager.refresh(includeReflogHistory: false)
    }

    func resetToLastCommit() {
        gitManager.resetToLastCommit()
        commentText = ""

        // Wait for reset to complete, then hide the main window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            closeWindow()
        }
    }

    func deleteRepository() {
        isDeleting = true

        Task {
            do {
                let repositoryService = GitHubRepositoryService(authManager: githubAuthManager)
                try await repositoryService.deleteRepository(remoteURL: gitManager.remoteUrl)

                await MainActor.run {
                    isDeleting = false
                    // Clear the remote URL since repo is deleted
                    gitManager.remoteUrl = ""
                    presentationModel.clearCreateRepoSuggestion()
                    closeWindow()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = error.localizedDescription
                }
            }
        }
    }

    func toggleRepoVisibility() {
        isTogglingVisibility = true
        let newStatus = !gitManager.isPrivate

        Task {
            do {
                let repositoryService = GitHubRepositoryService(authManager: githubAuthManager)
                _ = try await repositoryService.updateVisibility(
                    remoteURL: gitManager.remoteUrl,
                    isPrivate: newStatus
                )

                await MainActor.run {
                    isTogglingVisibility = false
                    gitManager.checkRepoVisibility()
                }
            } catch {
                await MainActor.run {
                    isTogglingVisibility = false
                    toggleVisibilityError = error.localizedDescription
                }
            }
        }
    }

    func selectDirectory() {
        setAutoHideSuspended(true)
        DirectoryPickerService().selectDirectory(activateApp: true) { path in
            self.setAutoHideSuspended(false)

            if let path {
                switchRepository(path: path)
            }
        }
    }

    func presentCommandPaletteIfPossible() {
        guard presentationModel.route == .main else {
            return
        }

        commandPaletteQuery = ""
        selectedCommandPaletteItemID = MainMenuCommandPaletteResolver.defaultSelectionID(
            for: commandPaletteVisibleItems
        )
        showProjectSelector = false
        showRepositoryOptionsPopover = false
        isCommandPalettePresented = true
    }

    func handleCommandPalettePresentationRequest(_ token: Int) {
        guard token > lastHandledCommandPaletteToken else {
            return
        }

        lastHandledCommandPaletteToken = token
        presentCommandPaletteIfPossible()
    }

    func handleRepositoryOptionsPresentationRequest(_ token: Int) {
        guard token > lastHandledRepositoryOptionsToken else {
            return
        }

        lastHandledRepositoryOptionsToken = token
        requestRepositoryOptionsPopoverPresentation()
    }

    func closeCommandPalette() {
        isCommandPalettePresented = false
        commandPaletteQuery = ""
        selectedCommandPaletteItemID = nil
    }

    func startAtomicCommitFlow() {
        guard !gitManager.changedFiles.isEmpty else { return }
        showAtomicCommitSheet = true
    }

    func dismissInlineStatusBanner() {
        guard let source = inlineStatusBannerSource else {
            return
        }

        switch source {
        case .coordinatorAlert, .deleteRepository, .toggleVisibility, .discard:
            dismissInlineBannerState(source)
        case .sync, .branchSwitch, .merge, .deleteBranch, .renameBranch, .restart, .push:
            dismissInlineBannerOperationError(source)
        }
    }

    private func dismissInlineBannerState(_ source: MainMenuInlineBannerSource) {
        switch source {
        case .coordinatorAlert:
            actionCoordinator.clearAlert()
        case .deleteRepository:
            deleteError = nil
        case .toggleVisibility:
            toggleVisibilityError = nil
        case .discard:
            discardError = nil
        default:
            break
        }
    }

    private func dismissInlineBannerOperationError(_ source: MainMenuInlineBannerSource) {
        switch source {
        case .sync:
            syncError = nil
        case .branchSwitch:
            branchSwitchError = nil
        case .merge:
            mergeError = nil
        case .deleteBranch:
            deleteBranchError = nil
        case .renameBranch:
            renameBranchError = nil
        case .restart:
            restartError = nil
        case .push:
            pushError = nil
        default:
            break
        }
    }

    func revealCommitFieldForManualEntry() {
        isCommitFieldTemporarilyVisible = true
        presentationModel.requestCommitFocus()
    }

    func startManualCommitMessageEdit(for commit: Commit) async {
        await commitHistoryEditCoordinator.beginManualEdit(for: commit)
    }

    func startAutomaticCommitMessageEdit(for commit: Commit) async {
        await commitHistoryEditCoordinator.beginAIGeneratedEdit(for: commit)
    }

    func saveEditedCommitMessage() async {
        let didRewrite = await commitHistoryEditCoordinator.saveDraftMessage()
        if didRewrite {
            presentationModel.showMain()
        }
    }

    func confirmPublishedCommitRewrite() async {
        let didRewrite = await commitHistoryEditCoordinator.confirmPublishedRewrite()
        if didRewrite {
            presentationModel.showMain()
        }
    }

    func restartApplication() {
        let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    restartError = error.localizedDescription
                    return
                }

                NSApplication.shared.terminate(nil)
            }
        }
    }

    func isCommitInFuture(_ commit: Commit) -> Bool {
        // A commit is "future" if it appears before current HEAD in the history list
        // This happens when we've reset backwards
        guard let currentIndex = gitManager.commitHistory.firstIndex(where: { $0.id == gitManager.currentHash }),
              let commitIndex = gitManager.commitHistory.firstIndex(where: { $0.id == commit.id })
        else {
            return false
        }
        return commitIndex < currentIndex
    }
}
