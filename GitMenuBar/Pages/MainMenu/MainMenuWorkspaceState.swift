import Foundation

@Observable
@MainActor
final class MainMenuWorkspaceState {
    // Commit composer
    var commentText = ""
    var isCommitFieldTemporarilyVisible = false

    // Selection
    var selectedMainItemID: MainMenuSelectableItem?
    var selectedSidePanelSelection: MainMenuSidePanelSelection?

    // Discard confirmations
    var showDiscardConfirmation = false
    var discardFilePath: String?
    var discardFileStatus: WorkingTreeFileStatus?
    var showDiscardAllConfirmation = false
}
