import SwiftUI

extension MainMenuView {
    private var shouldHandleMainKeyboardShortcuts: Bool {
        guard presentationModel.route == .main,
              // When the command palette is presented, MainMenuCommandPaletteView
              // owns arrow/enter/escape via onKeyPress on its focused search field.
              // This guard prevents the main list handler from competing with it.
              !palette.isPresented,
              !repoOptions.showProjectSelector,
              !branchDialogs.showBranchSelector,
              !branchDialogs.showCreateBranch,
              !sync.showPullToNewBranch,
              !branchDialogs.showRenameBranch,
              !commitHistoryEditCoordinator.isEditorPresented,
              !repoOptions.showRepositoryOptionsPopover
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
            repoOptions.showProjectSelector ? "1" : "0",
            branchDialogs.showBranchSelector ? "1" : "0",
            branchDialogs.showCreateBranch ? "1" : "0",
            sync.showPullToNewBranch ? "1" : "0",
            branchDialogs.showRenameBranch ? "1" : "0",
            commitHistoryEditCoordinator.isEditorPresented ? "1" : "0",
            repoOptions.showRepositoryOptionsPopover ? "1" : "0",
            isCommentFieldFocused ? "1" : "0"
        ].joined(separator: "|")
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
            workspace.moveMainSelection(.down, in: keyboardSelectableItems)
        case .upArrow:
            workspace.moveMainSelection(.up, in: keyboardSelectableItems)
        case .return:
            workspace.activateSelectedMainItem(openFile: { gitManager.openFile(path: $0) })
        case .delete, .deleteForward:
            workspace.discardSelectedMainItemIfPossible(changedFiles: gitManager.changedFiles)
        default:
            return .ignored
        }

        return .handled
    }
}
