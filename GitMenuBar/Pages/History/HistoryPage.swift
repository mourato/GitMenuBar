import SwiftUI

struct HistoryPageView: View {
    let commitHistory: [Commit]
    let currentHash: String
    let isCommitInFuture: (Commit) -> Bool
    let onDone: () -> Void
    let onSelectCommit: (Commit) -> Void

    var body: some View {
        VStack(spacing: 12) {
            InlinePageHeader(
                title: "History",
                systemImage: "clock",
                actionTitle: "Done",
                onAction: onDone
            )

            Divider()
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(commitHistory) { commit in
                        CommitRowView(
                            commit: commit,
                            isCurrentCommit: commit.id == currentHash,
                            isFutureCommit: isCommitInFuture(commit),
                            onTap: {
                                onSelectCommit(commit)
                            }
                        )

                        Divider()
                    }
                }
            }
            .frame(height: 200)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

#Preview("History Page") {
    HistoryPageView(
        commitHistory: [
            Commit(
                id: "abc1234",
                message: "feat(menu): add branch switcher",
                date: "2026-03-08",
                author: "octocat"
            ),
            Commit(
                id: "def5678",
                message: "fix(history): highlight current commit",
                date: "2026-03-07",
                author: "octocat"
            ),
            Commit(
                id: "ghi9012",
                message: "chore: tidy preview coverage",
                date: "2026-03-06",
                author: "octocat"
            )
        ],
        currentHash: "def5678",
        isCommitInFuture: { $0.id == "abc1234" },
        onDone: {},
        onSelectCommit: { _ in }
    )
    .frame(width: 420)
    .padding()
}
