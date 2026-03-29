import AppKit
import SwiftUI

extension MainMenuView {
    private enum MainViewKeyCode: UInt16 {
        case returnKey = 36
        case downArrow = 125
        case upArrow = 126
        case deleteKey = 51
        case forwardDelete = 117
    }

    private var shouldHandleMainKeyboardShortcuts: Bool {
        guard presentationModel.route == .main,
              !isCommandPalettePresented,
              !showBranchSelector,
              !showCreateBranch,
              !showPullToNewBranch,
              !showRenameBranch,
              !commitHistoryEditCoordinator.isEditorPresented,
              !showRepoOptions
        else {
            return false
        }

        return !isTextInputFocused
    }

    private var isTextInputFocused: Bool {
        if isCommentFieldFocused {
            return true
        }

        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }

        return textView.isEditable
    }

    func installMainKeyboardMonitor() {
        guard mainKeyboardMonitor == nil else {
            return
        }

        mainKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleMainKeyboardEvent(event) {
                return nil
            }

            return event
        }
    }

    func removeMainKeyboardMonitor() {
        guard let mainKeyboardMonitor else {
            return
        }

        NSEvent.removeMonitor(mainKeyboardMonitor)
        self.mainKeyboardMonitor = nil
    }

    func synchronizeSelectedMainItem() {
        guard let selectedMainItemID else {
            return
        }

        if keyboardSelectableItems.contains(selectedMainItemID) {
            return
        }

        self.selectedMainItemID = nil
    }

    func selectMainItem(_ itemID: MainMenuSelectableItem) {
        selectedMainItemID = itemID
    }

    func moveMainSelection(_ direction: MoveCommandDirection) {
        selectedMainItemID = MainMenuSelectionNavigator.moveSelection(
            currentSelection: selectedMainItemID,
            items: keyboardSelectableItems,
            direction: direction
        )
    }

    func activateSelectedMainItem() {
        guard let selectedMainItemID else {
            return
        }

        switch selectedMainItemID {
        case let .stagedFile(path), let .unstagedFile(path):
            gitManager.openFile(path: path)
        case let .historyCommit(id):
            presentationModel.showHistoryDetail(commitID: id)
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

    func handleMainKeyboardEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.numericPad)

        guard shouldHandleMainKeyboardShortcuts,
              !keyboardSelectableItems.isEmpty,
              modifiers.isEmpty
        else {
            return false
        }

        guard let keyCode = MainViewKeyCode(rawValue: event.keyCode) else {
            return false
        }

        switch keyCode {
        case .downArrow:
            moveMainSelection(.down)
        case .upArrow:
            moveMainSelection(.up)
        case .returnKey:
            activateSelectedMainItem()
        case .deleteKey, .forwardDelete:
            discardSelectedMainItemIfPossible()
        }

        return true
    }
}
