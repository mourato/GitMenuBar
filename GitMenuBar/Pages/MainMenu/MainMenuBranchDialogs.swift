import Foundation

@Observable
@MainActor
final class MainMenuBranchDialogs {
    // Branch selector popover
    var showBranchSelector = false

    // Create branch sheet
    var showCreateBranch = false
    var newBranchName = ""
    var createBranchError: String?

    // Rename branch sheet
    var showRenameBranch = false
    var oldBranchName = ""
    var renameBranchNewName = ""
    var renameBranchError: String?

    // Delete branch confirmation
    var showBranchDeleteConfirmation = false
    var branchNameToDelete = ""

    // Dirty switch confirmation
    var showDirtySwitchConfirmation = false
    var pendingSwitchBranch = ""

    // Merge confirmation
    var showMergeConfirmation = false
    var mergeBranchName = ""
    var mergeTargetBranch = ""

    // Merge-to-default flow
    var showMergeToDefaultConfirmation = false
    var showMergeCleanupDialog = false
    var showRemoteCleanupConfirmation = false
    var pendingCleanupOption: BranchCleanupOption?
    var featureBranchName = ""
    var defaultBranchName = ""
}
