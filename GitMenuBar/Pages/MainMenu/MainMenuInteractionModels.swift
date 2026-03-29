import Foundation
import SwiftUI

enum MainMenuSelectableItem: Hashable {
    case stagedFile(path: String)
    case unstagedFile(path: String)
    case historyCommit(id: String)
}

struct WorkingTreeItemActions: Equatable {
    let primaryLabel: String
    let accessibilityLabel: String
    let canDiscard: Bool
}

struct WorkingTreeRowAdapter: Identifiable, Equatable {
    let id: MainMenuSelectableItem
    let file: WorkingTreeFile
    let actions: WorkingTreeItemActions

    static func staged(file: WorkingTreeFile) -> WorkingTreeRowAdapter {
        WorkingTreeRowAdapter(
            id: .stagedFile(path: file.path),
            file: file,
            actions: WorkingTreeItemActions(
                primaryLabel: "Unstage file",
                accessibilityLabel: "Unstage \(file.fileName)",
                canDiscard: false
            )
        )
    }

    static func unstaged(file: WorkingTreeFile) -> WorkingTreeRowAdapter {
        WorkingTreeRowAdapter(
            id: .unstagedFile(path: file.path),
            file: file,
            actions: WorkingTreeItemActions(
                primaryLabel: "Stage file",
                accessibilityLabel: "Stage \(file.fileName)",
                canDiscard: true
            )
        )
    }
}

struct HistoryItemActions: Equatable {
    let canOpenOnGitHub: Bool
    let canEditMessage: Bool
    let canGenerateMessage: Bool
    let canRestore: Bool
}

struct HistoryRowAdapter: Identifiable, Equatable {
    let id: MainMenuSelectableItem
    let commit: Commit
    let actionSet: HistoryActionSet
    let actions: HistoryItemActions

    init(commit: Commit, currentHash: String, remoteUrl: String, isCommitInFuture: Bool) {
        let actionSet = HistoryActionSet(
            commit: commit,
            currentHash: currentHash,
            remoteUrl: remoteUrl,
            isCommitInFuture: isCommitInFuture
        )

        id = .historyCommit(id: commit.id)
        self.commit = commit
        self.actionSet = actionSet
        actions = HistoryItemActions(
            canOpenOnGitHub: actionSet.canOpenOnGitHub,
            canEditMessage: actionSet.canEditMessage,
            canGenerateMessage: actionSet.canGenerateMessage,
            canRestore: actionSet.canRestore
        )
    }
}

struct HistoryTimelineRowModel: Identifiable, Equatable {
    let row: HistoryRowAdapter
    let showsTopConnector: Bool
    let showsBottomConnector: Bool

    var id: MainMenuSelectableItem {
        row.id
    }
}

struct HistoryTimelineSectionModel: Identifiable, Equatable {
    let title: String
    let rows: [HistoryTimelineRowModel]

    var id: String {
        title
    }

    static func build(from rows: [HistoryRowAdapter]) -> [HistoryTimelineSectionModel] {
        let rowByCommitID = Dictionary(uniqueKeysWithValues: rows.map { ($0.commit.id, $0) })
        return HistoryCommitGrouping.group(commits: rows.map(\.commit)).map { section in
            let sectionRows = section.commits.compactMap { rowByCommitID[$0.id] }
            let timelineRows = sectionRows.enumerated().map { index, row in
                HistoryTimelineRowModel(
                    row: row,
                    showsTopConnector: index > 0,
                    showsBottomConnector: index < sectionRows.count - 1
                )
            }

            return HistoryTimelineSectionModel(title: section.title, rows: timelineRows)
        }
    }
}

enum MainMenuSelectionNavigator {
    static func moveSelection(
        currentSelection: MainMenuSelectableItem?,
        items: [MainMenuSelectableItem],
        direction: MoveCommandDirection
    ) -> MainMenuSelectableItem? {
        guard !items.isEmpty else {
            return nil
        }

        let step = selectionStep(for: direction)
        guard step != 0 else {
            return currentSelection
        }

        guard let currentSelection,
              let currentIndex = items.firstIndex(of: currentSelection)
        else {
            return step > 0 ? items.first : items.last
        }

        let targetIndex = max(0, min(items.count - 1, currentIndex + step))
        return items[targetIndex]
    }

    private static func selectionStep(for direction: MoveCommandDirection) -> Int {
        switch direction {
        case .down:
            return 1
        case .up:
            return -1
        default:
            return 0
        }
    }
}
