import Foundation
import SwiftUI

enum MainMenuOperationStatus: Equatable {
    case generatingCommitMessage
    case groupingChanges
    case committing
    case committingGroup(current: Int, total: Int)
    case pushing
    case pushingCommits(count: Int)

    var title: String {
        switch self {
        case .generatingCommitMessage:
            "Generating commit message…"
        case .groupingChanges:
            "Grouping changes…"
        case .committing:
            "Creating commit…"
        case let .committingGroup(current, total):
            "Creating commit \(current) of \(total)…"
        case .pushing:
            "Pushing to remote…"
        case let .pushingCommits(count):
            "Pushing \(count) commit\(count == 1 ? "" : "s")…"
        }
    }

    var progress: Double? {
        guard case let .committingGroup(current, total) = self, total > 0 else {
            return nil
        }
        return Double(current) / Double(total)
    }

    var accessibilityLabel: String {
        switch self {
        case .generatingCommitMessage:
            "Generating commit message"
        case .groupingChanges:
            "Grouping changes"
        case .committing:
            "Creating commit"
        case let .committingGroup(current, total):
            "Creating commit \(current) of \(total)"
        case .pushing:
            "Pushing to remote"
        case let .pushingCommits(count):
            "Pushing \(count) commit\(count == 1 ? "" : "s")"
        }
    }
}

enum MainMenuSelectableItem: Hashable {
    case stagedFile(path: String)
    case unstagedFile(path: String)
    case historyCommit(id: String)
}

enum MainMenuInspectorSelection: Hashable, Identifiable {
    case workingTree
    case branches
    case unpushedCommits
    case stashes
    case history
    case stagedFile(path: String)
    case unstagedFile(path: String)
    case branch(name: String)
    case stash(id: String)
    case commit(id: String)

    var id: String {
        switch self {
        case .workingTree: "working-tree"
        case .branches: "branches"
        case .unpushedCommits: "unpushed-commits"
        case .stashes: "stashes"
        case .history: "history"
        case let .stagedFile(path): "staged-file:\(path)"
        case let .unstagedFile(path): "unstaged-file:\(path)"
        case let .branch(name): "branch:\(name)"
        case let .stash(id): "stash:\(id)"
        case let .commit(id): "commit:\(id)"
        }
    }

    init?(mainMenuItem: MainMenuSelectableItem) {
        switch mainMenuItem {
        case let .stagedFile(path): self = .stagedFile(path: path)
        case let .unstagedFile(path): self = .unstagedFile(path: path)
        case let .historyCommit(id): self = .commit(id: id)
        }
    }

    var title: String {
        switch self {
        case .workingTree: "Working Tree"
        case .branches: "Branches"
        case .unpushedCommits: "Unpushed Commits"
        case .stashes: "Stashes"
        case .history: "History"
        case let .stagedFile(path), let .unstagedFile(path): path
        case let .branch(name): name
        case let .stash(id), let .commit(id): id
        }
    }
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
            1
        case .up:
            -1
        default:
            0
        }
    }
}
