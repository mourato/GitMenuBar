import Foundation

@Observable
@MainActor
final class MainMenuBranchDialogs {
    var showBranchSelector = false

    var showCreateBranch = false
    var newBranchName = ""
    var createBranchError: String?

    var showRenameBranch = false
    var oldBranchName = ""
    var renameBranchNewName = ""
    var renameBranchError: String?

    var showBranchDeleteConfirmation = false
    var branchNameToDelete = ""

    var showDirtySwitchConfirmation = false
    var pendingSwitchBranch = ""

    var showMergeConfirmation = false
    var mergeBranchName = ""
    var mergeTargetBranch = ""

    var showMergeToDefaultConfirmation = false
    var showMergeCleanupDialog = false
    var showRemoteCleanupConfirmation = false
    var pendingCleanupOption: BranchCleanupOption?
    var featureBranchName = ""
    var defaultBranchName = ""

    func createBranch(using actionCoordinator: MainMenuActionCoordinator) {
        createBranchError = nil
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            switch await actionCoordinator.createBranch(named: name) {
            case .succeeded:
                showCreateBranch = false
                newBranchName = ""
            case let .failed(message):
                createBranchError = message
            }
        }
    }

    func renameBranch(using actionCoordinator: MainMenuActionCoordinator, errorCenter: MainMenuErrorCenter) {
        errorCenter.renameBranch = nil
        let oldName = oldBranchName
        let newName = renameBranchNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        Task {
            switch await actionCoordinator.renameBranch(oldName: oldName, newName: newName) {
            case .succeeded:
                showRenameBranch = false
                renameBranchNewName = ""
                oldBranchName = ""
            case let .failed(message):
                errorCenter.renameBranch = message
            }
        }
    }

    func merge(using gitManager: GitManager, errorCenter: MainMenuErrorCenter) {
        gitManager.mergeBranch(fromBranch: mergeBranchName) { result in
            if case let .failure(error) = result {
                errorCenter.merge = error.localizedDescription
            }
        }
    }
}
