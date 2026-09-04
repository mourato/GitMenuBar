import SwiftUI

/// Shared history-surface input, built once by the workbench and consumed by
/// both the history inspector and the commit workspace. Replaces threading
/// the same dozen values through the inspector dispatcher.
struct InspectorHistoryModel {
    let sections: [HistoryTimelineSectionModel]
    let selectedItemID: MainMenuSelectableItem?
    let isLoading: Bool
    let canLoadMore: Bool
    let animationNamespace: Namespace.ID
    let isCommitInFuture: (Commit) -> Bool
    let onSelectRow: (HistoryRowAdapter) -> Void
    let onOpenCommit: (String) -> Void
    let onBackToHistory: () -> Void
    let onEditCommitMessage: (Commit) -> Void
    let onGenerateCommitMessage: (Commit) -> Void
    let onLoadMore: () -> Void
    let onOpenLocalFile: (String) -> Void

    static func preview(
        sections: [HistoryTimelineSectionModel] = [],
        selectedItemID: MainMenuSelectableItem? = nil,
        isLoading: Bool = false,
        canLoadMore: Bool = false
    ) -> InspectorHistoryModel {
        InspectorHistoryModel(
            sections: sections,
            selectedItemID: selectedItemID,
            isLoading: isLoading,
            canLoadMore: canLoadMore,
            animationNamespace: Namespace().wrappedValue,
            isCommitInFuture: { _ in false },
            onSelectRow: { _ in },
            onOpenCommit: { _ in },
            onBackToHistory: {},
            onEditCommitMessage: { _ in },
            onGenerateCommitMessage: { _ in },
            onLoadMore: {},
            onOpenLocalFile: { _ in }
        )
    }

    static var sampleSections: [HistoryTimelineSectionModel] {
        let commits = [
            Commit(
                id: "abc123",
                shortHash: "abc123",
                subject: "Fix critical bug in payment processing",
                body: "",
                authorName: "Alice",
                authorEmail: "alice@example.com",
                committedAt: Date(),
                stats: CommitStats(filesChanged: 3, insertions: 45, deletions: 12),
                changedFiles: []
            ),
            Commit(
                id: "def456",
                shortHash: "def456",
                subject: "Add unit tests for the new feature",
                body: "",
                authorName: "Bob",
                authorEmail: "bob@example.com",
                committedAt: Date().addingTimeInterval(-3600),
                stats: CommitStats(filesChanged: 1, insertions: 10, deletions: 0),
                changedFiles: []
            )
        ]
        let rows = commits.enumerated().map { index, commit in
            HistoryRowAdapter(
                commit: commit,
                currentHash: "abc123",
                remoteUrl: "https://github.com/example/repo.git",
                isCommitInFuture: index > 0
            )
        }
        return HistoryTimelineSectionModel.build(from: rows)
    }
}
