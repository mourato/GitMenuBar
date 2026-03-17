//
//  MainMenuActions.swift
//  GitMenuBar
//

import AppKit
import Foundation

extension MainMenuView {
    private var recentProjectsStore: RecentProjectsStore {
        RecentProjectsStore()
    }

    func submitComment() async {
        let result = await actionCoordinator.performCommit(commentText: commentText)
        if result.didCommit {
            commentText = ""
        }
    }

    func performPrimaryAction() async {
        if showsCommitAction {
            await submitComment()
            return
        }

        _ = await actionCoordinator.performSync()
    }

    func syncRepository() {
        Task {
            _ = await actionCoordinator.performSync()
        }
    }

    func syncWithRemote() {
        Task {
            _ = await actionCoordinator.syncWithRemote(rebase: useRebase)
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
        gitManager.stageFile(path: path) { result in
            if case let .failure(error) = result {
                syncError = error.localizedDescription
            }
        }
    }

    func stageAllFiles() {
        gitManager.stageAllChanges { result in
            if case let .failure(error) = result {
                syncError = error.localizedDescription
            }
        }
    }

    func unstageFile(path: String) {
        gitManager.unstageFile(path: path) { result in
            if case let .failure(error) = result {
                syncError = error.localizedDescription
            }
        }
    }

    func unstageAllFiles() {
        gitManager.unstageAllChanges { result in
            if case let .failure(error) = result {
                syncError = error.localizedDescription
            }
        }
    }

    func switchRepository(path: String, closeSettingsAfterRefresh: Bool = false) {
        if !gitManager.isGitRepository(at: path), githubAuthManager.isAuthenticated {
            presentationModel.showCreateRepo(path: path)
            return
        }

        setCurrentRepositoryPath(path)
        addToRecents(path)
        gitManager.refresh {
            if closeSettingsAfterRefresh {
                presentationModel.showMain(requestCommitFocus: true)
            }
        }
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

    func wipeRepository() {
        isWiping = true

        gitManager.wipeRepository { result in
            DispatchQueue.main.async {
                isWiping = false
                switch result {
                case .success:
                    presentationModel.showMain()
                    UserDefaults.standard.set(false, forKey: AppPreferences.Keys.showSettings)
                case let .failure(error):
                    wipeError = error.localizedDescription
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

    func addToRecents(_ path: String) {
        recentProjectsStore.add(path)
    }

    func setCurrentRepositoryPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
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
