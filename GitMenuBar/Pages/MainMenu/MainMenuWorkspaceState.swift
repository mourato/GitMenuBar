import SwiftUI

@Observable
@MainActor
final class MainMenuWorkspaceState {
    // Commit composer
    var commentText = ""
    var isCommitFieldTemporarilyVisible = false
    var showAtomicCommitSheet = false

    // Selection
    var selectedMainItemID: MainMenuSelectableItem?
    var selectedSidePanelSelection: MainMenuSidePanelSelection?

    // Discard confirmations
    var showDiscardConfirmation = false
    var discardFilePath: String?
    var discardFileStatus: WorkingTreeFileStatus?
    var showDiscardAllConfirmation = false

    func clearSidePanelSelection() {
        selectedSidePanelSelection = nil
    }

    func selectMainItem(_ itemID: MainMenuSelectableItem) {
        selectedMainItemID = itemID
        selectedSidePanelSelection = MainMenuSidePanelSelection(mainMenuItem: itemID)
    }

    /// Drops the main selection when it is no longer one of `items`.
    func synchronizeSelectedMainItem(with items: [MainMenuSelectableItem]) {
        guard let selectedMainItemID else {
            clearSidePanelSelection()
            return
        }

        if items.contains(selectedMainItemID) {
            return
        }

        self.selectedMainItemID = nil
        clearSidePanelSelection()
    }

    func moveMainSelection(_ direction: MoveCommandDirection, in items: [MainMenuSelectableItem]) {
        guard let nextSelection = MainMenuSelectionNavigator.moveSelection(
            currentSelection: selectedMainItemID,
            items: items,
            direction: direction
        ) else {
            selectedMainItemID = nil
            clearSidePanelSelection()
            return
        }

        selectMainItem(nextSelection)
    }

    func activateSelectedMainItem(openFile: (String) -> Void) {
        switch selectedMainItemID {
        case let .stagedFile(path), let .unstagedFile(path):
            openFile(path)
        case let .historyCommit(id):
            selectedSidePanelSelection = .commit(id: id)
        case nil:
            break
        }
    }

    func requestDiscard(path: String, status: WorkingTreeFileStatus) {
        discardFilePath = path
        discardFileStatus = status
        showDiscardConfirmation = true
    }

    func discardSelectedMainItemIfPossible(changedFiles: [WorkingTreeFile]) {
        guard case let .unstagedFile(path) = selectedMainItemID,
              let file = changedFiles.first(where: { $0.path == path })
        else {
            return
        }

        requestDiscard(path: file.path, status: file.status)
    }
}
