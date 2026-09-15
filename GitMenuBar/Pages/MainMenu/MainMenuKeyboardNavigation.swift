import SwiftUI

extension MainMenuView {
    private var shouldHandleMainKeyboardShortcuts: Bool {
        guard presentationModel.route == .main,
              // When the command palette is presented, MainMenuCommandPaletteView
              // owns arrow/enter/escape via onKeyPress on its focused search field.
              // This guard prevents the main list handler from competing with it.
              !palette.isPresented,
              !showProjectSelector,
              !showBranchSelector,
              !branchDialogs.showCreateBranch,
              !showPullToNewBranch,
              !branchDialogs.showRenameBranch,
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
            palette.isPresented ? "1" : "0",
            showProjectSelector ? "1" : "0",
            showBranchSelector ? "1" : "0",
            branchDialogs.showCreateBranch ? "1" : "0",
            showPullToNewBranch ? "1" : "0",
            branchDialogs.showRenameBranch ? "1" : "0",
            commitHistoryEditCoordinator.isEditorPresented ? "1" : "0",
            showRepositoryOptionsPopover ? "1" : "0",
            isCommentFieldFocused ? "1" : "0"
        ].joined(separator: "|")
    }

    func synchronizeSelectedMainItem() {
        guard let selectedMainItemID = workspace.selectedMainItemID else {
            clearSidePanelSelection()
            return
        }

        if keyboardSelectableItems.contains(selectedMainItemID) {
            return
        }

        workspace.selectedMainItemID = nil
        clearSidePanelSelection()
    }

    func clearSidePanelSelection() {
        workspace.selectedSidePanelSelection = nil
    }

    func selectMainItem(_ itemID: MainMenuSelectableItem) {
        workspace.selectedMainItemID = itemID
        workspace.selectedSidePanelSelection = MainMenuSidePanelSelection(mainMenuItem: itemID)
    }

    func moveMainSelection(_ direction: MoveCommandDirection) {
        guard let nextSelection = MainMenuSelectionNavigator.moveSelection(
            currentSelection: workspace.selectedMainItemID,
            items: keyboardSelectableItems,
            direction: direction
        ) else {
            workspace.selectedMainItemID = nil
            clearSidePanelSelection()
            return
        }

        selectMainItem(nextSelection)
    }

    func activateSelectedMainItem() {
        guard let selectedMainItemID = workspace.selectedMainItemID else {
            return
        }

        switch selectedMainItemID {
        case let .stagedFile(path), let .unstagedFile(path):
            gitManager.openFile(path: path)
        case let .historyCommit(id):
            workspace.selectedSidePanelSelection = .commit(id: id)
        }
    }

    func discardSelectedMainItemIfPossible() {
        guard let selectedMainItemID = workspace.selectedMainItemID else {
            return
        }

        guard case let .unstagedFile(path) = selectedMainItemID,
              let file = gitManager.changedFiles.first(where: { $0.path == path })
        else {
            return
        }

        workspace.discardFilePath = file.path
        workspace.discardFileStatus = file.status
        workspace.showDiscardConfirmation = true
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
