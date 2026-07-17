import SwiftUI

struct HistorySectionView: View {
    let sections: [HistoryTimelineSectionModel]
    let selectedItemID: MainMenuSelectableItem?
    let isLoading: Bool
    let canLoadMore: Bool
    let animationNamespace: Namespace.ID
    let onSelectRow: (HistoryRowAdapter) -> Void
    let onActivateCommit: (HistoryRowAdapter) -> Void
    let onRestoreCommit: (HistoryRowAdapter) -> Void
    let onEditCommitMessage: (HistoryRowAdapter) -> Void
    let onGenerateCommitMessage: (HistoryRowAdapter) -> Void
    let onLoadMore: () -> Void

    @Binding var isCollapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HistorySectionHeaderView(
                commitCount: sections.flatMap(\.rows).count,
                isCollapsed: $isCollapsed
            )

            if !isCollapsed {
                HistoryTimelineSectionView(
                    sections: sections,
                    selectedItemID: selectedItemID,
                    isLoading: isLoading,
                    animationNamespace: animationNamespace,
                    onSelectRow: onSelectRow,
                    onActivateCommit: onActivateCommit,
                    onRestoreCommit: onRestoreCommit,
                    onEditCommitMessage: onEditCommitMessage,
                    onGenerateCommitMessage: onGenerateCommitMessage
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))

                if canLoadMore {
                    HStack {
                        Spacer()

                        Button("Load 25 more") {
                            onLoadMore()
                        }
                        .buttonStyle(.link)
                        .font(MacChromeTypography.detail)
                        .disabled(isLoading)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.top, 2)
    }
}

#Preview("History Section") {
    HistorySectionView(
        sections: HistoryTimelineSectionModel.build(
            from: [
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
            ].enumerated().map { index, commit in
                HistoryRowAdapter(
                    commit: commit,
                    currentHash: "abc123",
                    remoteUrl: "https://github.com/user/repo",
                    isCommitInFuture: index > 0
                )
            }
        ),
        selectedItemID: nil,
        isLoading: false,
        canLoadMore: true,
        animationNamespace: Namespace().wrappedValue,
        onSelectRow: { _ in },
        onActivateCommit: { _ in },
        onRestoreCommit: { _ in },
        onEditCommitMessage: { _ in },
        onGenerateCommitMessage: { _ in },
        onLoadMore: {},
        isCollapsed: .constant(false)
    )
    .padding()
    .frame(width: 380)
}
