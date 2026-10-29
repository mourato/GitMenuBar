import SwiftUI

private enum CommitDetailPagePreviewData {
    static let commit = Commit(
        id: "1234567890abcdef1234567890abcdef12345678",
        shortHash: "1234567",
        subject: "feat(history): improve commit detail layout and actions",
        body: "Refines metadata, changed files presentation, and quick actions for commit inspection.",
        authorName: "Renato Silva",
        authorEmail: "renato@example.com",
        committedAt: .now.addingTimeInterval(-5400),
        stats: CommitStats(filesChanged: 3, insertions: 48, deletions: 12),
        changedFiles: [
            CommitFileChange(
                path: "GitMenuBar/Components/History/CommitDetailPageView.swift",
                lineDiff: LineDiffStats(added: 32, removed: 9)
            ),
            CommitFileChange(
                path: "GitMenuBar/Services/Git/GitManager.swift",
                lineDiff: LineDiffStats(added: 14, removed: 3)
            ),
            CommitFileChange(
                path: "README.md",
                lineDiff: LineDiffStats(added: 2, removed: 0)
            )
        ]
    )

    static let longSubjectCommit = Commit(
        id: "fedcba9876543210fedcba9876543210fedcba98",
        shortHash: "fedcba9",
        subject: "feat(history): keep the selected row title visible while the open commit detail panel shows the same commit with its full metadata",
        body: "",
        authorName: "Renato Silva",
        authorEmail: "renato@example.com",
        committedAt: .now.addingTimeInterval(-7200),
        stats: CommitStats(filesChanged: 1, insertions: 6, deletions: 1),
        changedFiles: [
            CommitFileChange(
                path: "GitMenuBar/Components/History/HistoryTimelineSectionView.swift",
                lineDiff: LineDiffStats(added: 6, removed: 1)
            )
        ]
    )
}

#if DEBUG
    #Preview("Commit Detail") {
        CommitDetailPageView(
            commit: CommitDetailPagePreviewData.commit,
            currentHash: "abcdef1234567890",
            remoteUrl: "https://github.com/example/repo.git",
            isCommitInFuture: { _ in false },
            onBack: {},
            onRestoreCommit: { _ in },
            onEditCommitMessage: { _ in },
            onGenerateCommitMessage: { _ in }
        )
        .environment(
            GitHubAuthManager(
                tokenStore: InMemoryGitHubTokenStore(),
                preloadStoredToken: false
            )
        )
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
        .frame(width: 420, height: 580)
    }

    #Preview("Commit Detail - Long Subject") {
        CommitDetailPageView(
            commit: CommitDetailPagePreviewData.longSubjectCommit,
            currentHash: "abcdef1234567890",
            remoteUrl: "https://github.com/example/repo.git",
            isCommitInFuture: { _ in false },
            onBack: {},
            onRestoreCommit: { _ in },
            onEditCommitMessage: { _ in },
            onGenerateCommitMessage: { _ in }
        )
        .environment(
            GitHubAuthManager(
                tokenStore: InMemoryGitHubTokenStore(),
                preloadStoredToken: false
            )
        )
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
        .frame(width: 420, height: 580)
    }

    #Preview("Commit Detail - Missing Commit") {
        CommitDetailPageView(
            commit: nil,
            currentHash: "abcdef1234567890",
            remoteUrl: "https://github.com/example/repo.git",
            isCommitInFuture: { _ in false },
            onBack: {},
            onRestoreCommit: { _ in },
            onEditCommitMessage: { _ in },
            onGenerateCommitMessage: { _ in }
        )
        .environment(
            GitHubAuthManager(
                tokenStore: InMemoryGitHubTokenStore(),
                preloadStoredToken: false
            )
        )
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
        .frame(width: 420)
    }

#endif
