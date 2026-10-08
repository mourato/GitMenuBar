import AppKit
import SwiftUI

/// Branch switch, delete, merge, and merge-to-default cleanup confirmations.
/// Owns the actions behind each confirmation; reports failures to `errorCenter`.
struct BranchConfirmationDialogsModifier: ViewModifier {
    @Bindable var dialogs: MainMenuBranchDialogs
    let errorCenter: MainMenuErrorCenter
    @Environment(GitManager.self) private var gitManager
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator

    func body(content: Content) -> some View {
        content
            .alert("Merge into \(dialogs.mergeTargetBranch)?", isPresented: $dialogs.showMergeConfirmation) {
                Button("Merge", action: merge)
                Button("Cancel", role: .cancel) {
                    dialogs.mergeBranchName = ""
                    dialogs.mergeTargetBranch = ""
                }
            } message: {
                Text("This will bring all changes from '\(dialogs.mergeBranchName)' into your current branch '\(dialogs.mergeTargetBranch)'.")
            }
            .alert("Uncommitted Changes", isPresented: $dialogs.showDirtySwitchConfirmation) {
                Button("Switch & Carry Over", action: switchCarryingChanges)
                Button("Cancel", role: .cancel) {
                    dialogs.pendingSwitchBranch = ""
                }
            } message: {
                Text("You have uncommitted changes. They will follow you to '\(dialogs.pendingSwitchBranch)'.")
            }
            .alert("Delete '\(dialogs.branchNameToDelete)'?", isPresented: $dialogs.showBranchDeleteConfirmation) {
                Button("Delete", role: .destructive, action: deleteBranch)
                Button("Cancel", role: .cancel) {
                    dialogs.branchNameToDelete = ""
                }
            } message: {
                Text(deleteBranchWarningMessage)
            }
            .alert("Merge '\(dialogs.featureBranchName)' into \(dialogs.defaultBranchName)?", isPresented: $dialogs.showMergeToDefaultConfirmation) {
                Button("Merge", action: performMergeToDefault)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    dialogs.featureBranchName = ""
                    dialogs.defaultBranchName = ""
                }
            } message: {
                Text("This brings all changes from '\(dialogs.featureBranchName)' into \(dialogs.defaultBranchName). Uncommitted changes are stashed and restored. The feature branch is kept so you can clean it up afterwards.")
            }
            .confirmationDialog("Clean up '\(dialogs.featureBranchName)'?", isPresented: $dialogs.showMergeCleanupDialog, titleVisibility: .visible) {
                Button("Delete Local Only", role: .destructive) { performMergeCleanup(option: .deleteLocal) }
                Button("Delete Local & Remote", role: .destructive) { requestRemoteCleanupConfirmation(option: .deleteLocalAndRemote) }
                Button("Delete Remote Only", role: .destructive) { requestRemoteCleanupConfirmation(option: .deleteRemoteOnly) }
                Button("Keep Branch", role: .cancel, action: dismissMergeCleanup)
            } message: {
                Text("'\(dialogs.featureBranchName)' is merged into \(dialogs.defaultBranchName). You can delete the feature branch now or keep it.")
            }
            .alert("Delete remote branch '\(dialogs.featureBranchName)'?", isPresented: $dialogs.showRemoteCleanupConfirmation) {
                Button("Delete Remote", role: .destructive) {
                    if let option = dialogs.pendingCleanupOption {
                        performMergeCleanup(option: option)
                    }
                    dialogs.pendingCleanupOption = nil
                }
                Button("Cancel", role: .cancel) {
                    dialogs.pendingCleanupOption = nil
                }
            } message: {
                Text("This permanently removes '\(dialogs.featureBranchName)' from the remote. Other collaborators may be affected, and this cannot be undone.")
            }
    }

    private var deleteBranchWarningMessage: String {
        let protectedBranches = ["main", "master", "develop"]
        if gitManager.unmergedIntoDefaultBranches.contains(dialogs.branchNameToDelete) {
            return "This branch is not merged into the default branch. Git will keep it unless you review its removal in Cleanup."
        }
        if protectedBranches.contains(dialogs.branchNameToDelete) {
            return "WARNING: '\(dialogs.branchNameToDelete)' is a primary branch. Deleting it may cause serious issues."
        }

        return "Are you sure you want to delete this branch? This action cannot be undone."
    }

    private func merge() {
        gitManager.mergeBranch(fromBranch: dialogs.mergeBranchName) { result in
            if case let .failure(error) = result {
                errorCenter.merge = error.localizedDescription
            }
        }
    }

    private func switchCarryingChanges() {
        let branch = dialogs.pendingSwitchBranch
        dialogs.pendingSwitchBranch = ""
        guard !branch.isEmpty else { return }
        Task {
            _ = await actionCoordinator.switchSidePanelBranch(branch)
        }
    }

    private func deleteBranch() {
        let name = dialogs.branchNameToDelete
        dialogs.branchNameToDelete = ""
        Task {
            _ = await actionCoordinator.deleteSidePanelBranch(name)
        }
    }

    private func performMergeToDefault() {
        let featureBranch = dialogs.featureBranchName
        dialogs.showMergeToDefaultConfirmation = false

        guard !featureBranch.isEmpty else { return }

        Task {
            switch await actionCoordinator.mergeFeatureIntoDefault(featureBranch: featureBranch) {
            case .succeeded:
                dialogs.showMergeCleanupDialog = true
            case let .failed(message):
                dialogs.featureBranchName = ""
                dialogs.defaultBranchName = ""
                errorCenter.merge = message
            }
        }
    }

    private func requestRemoteCleanupConfirmation(option: BranchCleanupOption) {
        dialogs.pendingCleanupOption = option
        dialogs.showRemoteCleanupConfirmation = true
    }

    private func dismissMergeCleanup() {
        dialogs.showMergeCleanupDialog = false
        dialogs.featureBranchName = ""
        dialogs.defaultBranchName = ""
        dialogs.pendingCleanupOption = nil
    }

    private func performMergeCleanup(option: BranchCleanupOption) {
        let featureBranch = dialogs.featureBranchName
        dialogs.showMergeCleanupDialog = false
        dialogs.showRemoteCleanupConfirmation = false
        dialogs.featureBranchName = ""
        dialogs.defaultBranchName = ""
        dialogs.pendingCleanupOption = nil

        guard !featureBranch.isEmpty else { return }

        Task {
            let result = await actionCoordinator.cleanupMergedBranch(
                featureBranch: featureBranch,
                cleanupOption: option
            )
            if case let .failed(message) = result {
                errorCenter.merge = message
            }
        }
    }
}

/// Repository delete/visibility, discard, and restart confirmations.
/// Owns the actions behind each confirmation; reports failures to `errorCenter`.
struct RepositoryConfirmationDialogsModifier: ViewModifier {
    @Bindable var confirmations: MainMenuRepositoryConfirmations
    @Bindable var workspace: MainMenuWorkspaceState
    let errorCenter: MainMenuErrorCenter
    let repositoryActionSet: RepositoryActionSet
    let closeWindow: () -> Void
    @Environment(GitManager.self) private var gitManager
    @Environment(GitHubAuthManager.self) private var githubAuthManager
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator
    @Environment(MainMenuPresentationModel.self) private var presentationModel

    func body(content: Content) -> some View {
        content
            .alert("Delete Repository?", isPresented: $confirmations.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: deleteRepository)
                    .keyboardShortcut(.defaultAction)
                    .disabled(confirmations.isDeleting)
            } message: {
                Text("This will permanently delete the repository from GitHub. This action cannot be undone.")
            }
            .alert(repositoryActionSet.visibilityConfirmationTitle, isPresented: $confirmations.showVisibilityConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button(repositoryActionSet.visibilityActionTitle, action: toggleRepoVisibility)
                    .keyboardShortcut(.defaultAction)
                    .disabled(confirmations.isTogglingVisibility)
            } message: {
                Text(repositoryActionSet.visibilityConfirmationMessage)
            }
            .alert("Discard Changes?", isPresented: $workspace.showDiscardConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive, action: discardFile)
                    .keyboardShortcut(.defaultAction)
            }
            .alert("Discard All Unstaged Changes?", isPresented: $workspace.showDiscardAllConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Discard All", role: .destructive, action: discardAll)
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text("Are you sure you want to discard all unstaged changes? This action cannot be undone.")
            }
            .alert("Restart GitMenuBar?", isPresented: $confirmations.showRestartConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Restart", action: restartApplication)
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text("This will relaunch the app immediately.")
            }
    }

    private func discardFile() {
        if let path = workspace.discardFilePath, let status = workspace.discardFileStatus {
            Task {
                _ = await actionCoordinator.discardSidePanelFile(path: path, status: status)
            }
        }
        workspace.discardFilePath = nil
        workspace.discardFileStatus = nil
    }

    private func discardAll() {
        gitManager.discardAllUnstagedChanges { result in
            if case let .failure(error) = result {
                errorCenter.discard = error.localizedDescription
            }
        }
    }

    private func deleteRepository() {
        confirmations.isDeleting = true

        Task {
            do {
                let repositoryService = GitHubRepositoryService(authManager: githubAuthManager)
                try await repositoryService.deleteRepository(remoteURL: gitManager.remoteUrl)
                confirmations.isDeleting = false
                // Clear the remote URL since repo is deleted
                gitManager.remoteUrl = ""
                presentationModel.clearCreateRepoSuggestion()
                closeWindow()
            } catch {
                confirmations.isDeleting = false
                errorCenter.deleteRepository = error.localizedDescription
            }
        }
    }

    private func toggleRepoVisibility() {
        confirmations.isTogglingVisibility = true
        let newStatus = !gitManager.isPrivate

        Task {
            do {
                let repositoryService = GitHubRepositoryService(authManager: githubAuthManager)
                _ = try await repositoryService.updateVisibility(
                    remoteURL: gitManager.remoteUrl,
                    isPrivate: newStatus
                )
                confirmations.isTogglingVisibility = false
                gitManager.checkRepoVisibility()
            } catch {
                confirmations.isTogglingVisibility = false
                errorCenter.toggleVisibility = error.localizedDescription
            }
        }
    }

    private func restartApplication() {
        let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    errorCenter.restart = error.localizedDescription
                    return
                }

                NSApplication.shared.terminate(nil)
            }
        }
    }
}
