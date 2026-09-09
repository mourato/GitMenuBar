import SwiftUI

extension MainMenuView {
    private var shouldHandleMainKeyboardShortcuts: Bool {
        guard presentationModel.route == .main,
              // When the command palette is presented, MainMenuCommandPaletteView
              // owns arrow/enter/escape via onKeyPress on its focused search field.
              // This guard prevents the main list handler from competing with it.
              !isCommandPalettePresented,
              !showProjectSelector,
              !showBranchSelector,
              !showCreateBranch,
              !showPullToNewBranch,
              !showRenameBranch,
              !commitHistoryEditCoordinator.isEditorPresented,
              !showRepositoryOptionsPopover
        else {
            return false
        }

        return !isCommentFieldFocused
    }

    func synchronizeMainKeyboardNavigationFocus() {
        guard shouldHandleMainKeyboardShortcuts else {
            return
        }

        isMainKeyboardNavigationFocused = true
    }

    /// Collapses overlay/focus distractors so MainMenuView can resync keyboard focus in one onChange.
    var mainKeyboardFocusSyncToken: String {
        [
            presentationModel.route == .main ? "main" : "other",
            isCommandPalettePresented ? "1" : "0",
            showProjectSelector ? "1" : "0",
            showBranchSelector ? "1" : "0",
            showCreateBranch ? "1" : "0",
            showPullToNewBranch ? "1" : "0",
            showRenameBranch ? "1" : "0",
            commitHistoryEditCoordinator.isEditorPresented ? "1" : "0",
            showRepositoryOptionsPopover ? "1" : "0",
            isCommentFieldFocused ? "1" : "0"
        ].joined(separator: "|")
    }

    func synchronizeSelectedMainItem() {
        guard let selectedMainItemID else {
            clearSidePanelSelection()
            return
        }

        if keyboardSelectableItems.contains(selectedMainItemID) {
            return
        }

        self.selectedMainItemID = nil
        clearSidePanelSelection()
    }

    func clearSidePanelSelection() {
        selectedSidePanelSelection = nil
    }

    func selectMainItem(_ itemID: MainMenuSelectableItem) {
        selectedMainItemID = itemID
        selectedSidePanelSelection = MainMenuSidePanelSelection(mainMenuItem: itemID)
    }

    func moveMainSelection(_ direction: MoveCommandDirection) {
        guard let nextSelection = MainMenuSelectionNavigator.moveSelection(
            currentSelection: selectedMainItemID,
            items: keyboardSelectableItems,
            direction: direction
        ) else {
            selectedMainItemID = nil
            clearSidePanelSelection()
            return
        }

        selectMainItem(nextSelection)
    }

    func activateSelectedMainItem() {
        guard let selectedMainItemID else {
            return
        }

        switch selectedMainItemID {
        case let .stagedFile(path), let .unstagedFile(path):
            gitManager.openFile(path: path)
        case let .historyCommit(id):
            selectedSidePanelSelection = .commit(id: id)
        }
    }

    func discardSelectedMainItemIfPossible() {
        guard let selectedMainItemID else {
            return
        }

        guard case let .unstagedFile(path) = selectedMainItemID,
              let file = gitManager.changedFiles.first(where: { $0.path == path })
        else {
            return
        }

        discardFilePath = file.path
        discardFileStatus = file.status
        showDiscardConfirmation = true
    }

    func handleMainKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard shouldHandleMainKeyboardShortcuts,
              !keyboardSelectableItems.isEmpty,
              keyPress.modifiers.isEmpty
        else {
            return .ignored
        }

        switch keyPress.key {
        case .downArrow:
            moveMainSelection(.down)
        case .upArrow:
            moveMainSelection(.up)
        case .return:
            activateSelectedMainItem()
        case .delete, .deleteForward:
            discardSelectedMainItemIfPossible()
        default:
            return .ignored
        }

        return .handled
    }
}
