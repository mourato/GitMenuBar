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
