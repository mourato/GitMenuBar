//
//  MainMenuActions.swift
//  GitMenuBar
//

import AppKit
import Foundation

extension MainMenuView {
    func submitComment() {
        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard !gitManager.isCommitting else { return }
        guard !aiCommitCoordinator.isGenerating else { return }
        guard hasWorkingTreeChanges else { return }

        commentText = ""

        // Commit staged files first, or auto-stage changes when staged is empty.
        gitManager.commitLocallyWithFallback(trimmedText) {
            self.gitManager.refresh()
        }
    }

    func performPrimaryAction() {
        guard hasWorkingTreeChanges else { return }
        submitComment()
    }

    func syncRepository() {
        guard !aiCommitCoordinator.isGenerating, !gitManager.isCommitting else { return }
        if gitManager.isRemoteAhead {
            showSyncOptions = true
            return
        }

        gitManager.pushToRemote { result in
            switch result {
            case .success:
                self.gitManager.refresh()
            case let .failure(error):
                self.pushError = error.localizedDescription
            }
        }
    }

    func generateCommitMessageFromPriorityScope() {
        guard !aiCommitCoordinator.isGenerating else { return }
        guard hasWorkingTreeChanges else { return }

        let scope: DiffScope = gitManager.stagedFiles.isEmpty ? .unstaged : .staged

        Task {
            do {
                let generated = try await aiCommitCoordinator.generateMessage(scopeOverride: scope)
                commentText = generated
            } catch {
                // The coordinator already publishes a user-facing error string.
            }
        }
    }

    func syncWithRemote() {
        showSyncOptions = false
        gitManager.pullFromRemote(rebase: useRebase) { result in
            switch result {
            case .success:
                self.gitManager.pushToRemote { pushResult in
                    switch pushResult {
                    case .success:
                        self.gitManager.refresh()
                    case let .failure(error):
                        self.pushError = error.localizedDescription
                    }
                }
            case let .failure(error):
                self.syncError = error.localizedDescription
            }
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
            createRepoPath = CreateRepoPath(path: path)
            return
        }

        UserDefaults.standard.set(path, forKey: "gitRepoPath")
        addToRecents(path)
        gitManager.refresh {
            if closeSettingsAfterRefresh {
                showingSettings = false
            }
        }
    }

    func resetToLastCommit() {
        gitManager.resetToLastCommit()
        commentText = ""

        // Wait for reset to complete, then close popover
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            closePopover()
        }
    }

    func deleteRepository() {
        // Parse owner and repo name from remote URL
        // Supports formats like:
        // https://github.com/owner/repo.git
        // https://github.com/owner/repo
        // git@github.com:owner/repo.git

        let remoteUrl = gitManager.remoteUrl
        var owner: String?
        var repoName: String?

        if remoteUrl.contains("github.com") {
            // HTTPS format: https://github.com/owner/repo.git
            if let url = URL(string: remoteUrl) {
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                if pathComponents.count >= 2 {
                    owner = pathComponents[0]
                    repoName = pathComponents[1].replacingOccurrences(of: ".git", with: "")
                }
            }
            // SSH format: git@github.com:owner/repo.git
            else if remoteUrl.hasPrefix("git@github.com:") {
                let path = remoteUrl.replacingOccurrences(of: "git@github.com:", with: "")
                let parts = path.split(separator: "/")
                if parts.count >= 2 {
                    owner = String(parts[0])
                    repoName = String(parts[1]).replacingOccurrences(of: ".git", with: "")
                }
            }
        }

        guard let owner = owner, let repoName = repoName else {
            deleteError = "Could not parse repository owner and name from remote URL"
            return
        }

        isDeleting = true

        Task {
            do {
                let apiClient = GitHubAPIClient(authManager: githubAuthManager)
                try await apiClient.deleteRepository(owner: owner, name: repoName)

                await MainActor.run {
                    isDeleting = false
                    // Clear the remote URL since repo is deleted
                    gitManager.remoteUrl = ""
                    closePopover()
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
        let remoteUrl = gitManager.remoteUrl
        var owner: String?
        var repoName: String?

        if remoteUrl.contains("github.com") {
            // HTTPS format: https://github.com/owner/repo.git
            if let url = URL(string: remoteUrl) {
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                if pathComponents.count >= 2 {
                    owner = pathComponents[0]
                    repoName = pathComponents[1].replacingOccurrences(of: ".git", with: "")
                }
            }
            // SSH format: git@github.com:owner/repo.git
            else if remoteUrl.hasPrefix("git@github.com:") {
                let path = remoteUrl.replacingOccurrences(of: "git@github.com:", with: "")
                let parts = path.split(separator: "/")
                if parts.count >= 2 {
                    owner = String(parts[0])
                    repoName = String(parts[1]).replacingOccurrences(of: ".git", with: "")
                }
            }
        }

        guard let owner = owner, let repoName = repoName else {
            toggleVisibilityError = "Could not parse repository owner and name from remote URL"
            return
        }

        isTogglingVisibility = true
        let newStatus = !gitManager.isPrivate

        Task {
            do {
                let apiClient = GitHubAPIClient(authManager: githubAuthManager)
                _ = try await apiClient.updateRepositoryVisibility(owner: owner, name: repoName, isPrivate: newStatus)

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
                    showingSettings = false
                    UserDefaults.standard.set(false, forKey: "showSettings")
                case let .failure(error):
                    wipeError = error.localizedDescription
                }
            }
        }
    }

    func selectDirectory() {
        NSApp.activate(ignoringOtherApps: true)

        // Keep popover open while file dialog is shown
        togglePopoverBehavior()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Select Git Repository"
        panel.prompt = "Choose"
        panel.worksWhenModal = false

        // Make panel appear on top
        DispatchQueue.main.async {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }

        panel.begin { result in
            // Restore popover behavior
            self.togglePopoverBehavior()

            if result == .OK, let url = panel.url {
                let path = url.path
                switchRepository(path: path)
            }
        }
    }

    func addToRecents(_ path: String) {
        var current = recentPaths
        // Remove if exists to move to top
        current.removeAll { $0 == path }
        // Add to top
        current.insert(path, at: 0)
        // Keep only last 5 to ensure we have enough to show 3 others
        if current.count > 5 {
            current = Array(current.prefix(5))
        }

        if let encoded = try? JSONEncoder().encode(current) {
            recentRepoPathsData = encoded
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
