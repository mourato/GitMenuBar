import SwiftUI

struct HistoryPageView: View {
    let commitHistory: [Commit]
    let currentHash: String
    let remoteUrl: String
    let isLoading: Bool
    let isCommitInFuture: (Commit) -> Bool
    let onDone: () -> Void
    let onRestoreCommit: (Commit) -> Void

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
                HistoryTimelineSectionView(
                    commits: commitHistory,
                    currentHash: currentHash,
                    remoteUrl: remoteUrl,
                    isLoading: isLoading,
                    showsHeader: false,
                    isCommitInFuture: isCommitInFuture,
                    onRestoreCommit: onRestoreCommit
                )
            }
            .frame(height: 280)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

#Preview("History Page") {
    HistoryPageView(
        commitHistory: [
            Commit(
                id: "abc1234def5678",
                shortHash: "abc1234",
                subject: "feat(menu): add branch switcher",
                body: "",
                authorName: "octocat",
                authorEmail: "octocat@example.com",
                committedAt: .now.addingTimeInterval(-1200),
                stats: CommitStats(filesChanged: 2, insertions: 24, deletions: 6),
                changedFiles: [
                    CommitFileChange(path: "GitMenuBar/Components/Branches/BranchSelectorPopover.swift", lineDiff: LineDiffStats(added: 20, removed: 4)),
                    CommitFileChange(path: "GitMenuBar/Pages/MainMenu/MainMenuView.swift", lineDiff: LineDiffStats(added: 4, removed: 2))
                ]
            ),
            Commit(
                id: "def5678abc1234",
                shortHash: "def5678",
                subject: "fix(history): highlight current commit",
                body: "",
                authorName: "octocat",
                authorEmail: "octocat@example.com",
                committedAt: .now.addingTimeInterval(-86400),
                stats: CommitStats(filesChanged: 1, insertions: 8, deletions: 3),
                changedFiles: [
                    CommitFileChange(path: "GitMenuBar/Components/History/HistoryTimelineSectionView.swift", lineDiff: LineDiffStats(added: 8, removed: 3))
                ]
            )
        ],
        currentHash: "def5678abc1234",
        remoteUrl: "https://github.com/example/gitmenubar",
        isLoading: false,
        isCommitInFuture: { $0.id == "abc1234def5678" },
        onDone: {},
        onRestoreCommit: { _ in }
    )
    .frame(width: 420)
    .padding()
}
