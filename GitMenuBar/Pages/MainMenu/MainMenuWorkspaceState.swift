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

    /// Highlights a file inside the working tree panel without replacing the panel.
    func selectWorkspaceFile(_ itemID: MainMenuSelectableItem) {
        selectedMainItemID = itemID
    }

    /// Keeps a selected file attached to its working-tree row when staging
    /// moves that row between sections. The old semantic ID must disappear
    /// before its counterpart can replace it, so partial staging cannot mix
    /// two visible rows for the same path.
    func synchronizeSelectedMainItem(with items: [MainMenuSelectableItem]) {
        guard let previousSelection = selectedMainItemID, !items.contains(previousSelection) else {
            return
        }

        if let replacement = Self.counterpart(of: previousSelection), items.contains(replacement) {
            selectedMainItemID = replacement
            if selectedSidePanelSelection == MainMenuSidePanelSelection(mainMenuItem: previousSelection) {
                selectedSidePanelSelection = MainMenuSidePanelSelection(mainMenuItem: replacement)
            }
            return
        }

        selectedMainItemID = nil
        if selectedSidePanelSelection == MainMenuSidePanelSelection(mainMenuItem: previousSelection) {
            selectedSidePanelSelection = Self.parentSidePanelSelection(for: previousSelection)
        }
    }

    private static func counterpart(of itemID: MainMenuSelectableItem) -> MainMenuSelectableItem? {
        switch itemID {
        case let .stagedFile(path): .unstagedFile(path: path)
        case let .unstagedFile(path): .stagedFile(path: path)
        case .historyCommit: nil
        }
    }

    private static func parentSidePanelSelection(for itemID: MainMenuSelectableItem) -> MainMenuSidePanelSelection {
        switch itemID {
        case .stagedFile, .unstagedFile: .workingTree
        case .historyCommit: .history
        }
    }

    func moveMainSelection(_ direction: MoveCommandDirection, in items: [MainMenuSelectableItem]) {
        guard let nextSelection = MainMenuSelectionNavigator.moveSelection(
            currentSelection: selectedMainItemID,
            items: items,
            direction: direction
        ) else {
            selectedMainItemID = nil
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

    func discardFile(using actionCoordinator: MainMenuActionCoordinator) {
        if let path = discardFilePath, let status = discardFileStatus {
            Task {
                _ = await actionCoordinator.sidePanel.discardSidePanelFile(path: path, status: status)
            }
        }
        discardFilePath = nil
        discardFileStatus = nil
    }

    func discardAll(using gitManager: GitManager, errorCenter: MainMenuErrorCenter) {
        gitManager.discardAllUnstagedChanges { result in
            if case let .failure(error) = result {
                errorCenter.discard = error.localizedDescription
            }
        }
    }
}
