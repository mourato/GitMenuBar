import SwiftUI

private enum CommitDetailPagePreviewData {
    static let baseCommit = Commit(
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
        id: "abcdef1234567890abcdef1234567890abcdef12",
        shortHash: "abcdef1",
        subject: "feat(history): improve commit detail layout and actions with an exceptionally long title that wraps across multiple lines in the side panel header hierarchy to test three-line limit truncation and wrapping behavior",
        body: "Refines metadata, changed files presentation, and quick actions for commit inspection.",
        authorName: "Renato Silva",
        authorEmail: "renato@example.com",
        committedAt: .now.addingTimeInterval(-7200),
        stats: CommitStats(filesChanged: 3, insertions: 48, deletions: 12),
        changedFiles: baseCommit.changedFiles
    )

    static let mergeCommit = Commit(
        id: "fedcba0987654321fedcba0987654321fedcba09",
        shortHash: "fedcba0",
        subject: "Merge branch 'feat/commit-inspector' into main",
        body: "",
        authorName: "Renato Silva",
        authorEmail: "renato@example.com",
        committedAt: .now.addingTimeInterval(-10800),
        isMergeCommit: true,
        stats: CommitStats(filesChanged: 8, insertions: 120, deletions: 30),
        changedFiles: baseCommit.changedFiles
    )

    static let noBodyCommit = Commit(
        id: "5678901234abcdef5678901234abcdef56789012",
        shortHash: "5678901",
        subject: "chore(deps): update Swift package dependencies to latest minor versions",
        body: "",
        authorName: "Renato Silva",
        authorEmail: "renato@example.com",
        committedAt: .now.addingTimeInterval(-14400),
        stats: CommitStats(filesChanged: 1, insertions: 2, deletions: 2),
        changedFiles: [
            CommitFileChange(
                path: "Package.resolved",
                lineDiff: LineDiffStats(added: 2, removed: 2)
            )
        ]
    )
}

private struct CommitDetailPreviewContainer: View {
    let commit: Commit?
    var remoteUrl: String = "https://github.com/example/repo.git"
    @Namespace private var animationNamespace

    var body: some View {
        CommitDetailPageView(
            commit: commit,
            currentHash: "1234567890abcdef1234567890abcdef12345678",
            remoteUrl: remoteUrl,
            isCommitInFuture: { _ in false },
            animationNamespace: animationNamespace,
            onClose: {},
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
        .padding(WorkbenchMetrics.panelPadding)
        .frame(width: WorkbenchMetrics.sidePanelWidth, height: 580)
    }
}

#if DEBUG
    #Preview("Commit Detail - Default") {
        CommitDetailPreviewContainer(commit: CommitDetailPagePreviewData.baseCommit)
    }

    #Preview("Commit Detail - Long Subject") {
        CommitDetailPreviewContainer(commit: CommitDetailPagePreviewData.longSubjectCommit)
    }

    #Preview("Commit Detail - Merge Commit") {
        CommitDetailPreviewContainer(commit: CommitDetailPagePreviewData.mergeCommit)
    }

    #Preview("Commit Detail - No Body") {
        CommitDetailPreviewContainer(commit: CommitDetailPagePreviewData.noBodyCommit)
    }

    #Preview("Commit Detail - No GitHub Remote") {
        CommitDetailPreviewContainer(
            commit: CommitDetailPagePreviewData.baseCommit,
            remoteUrl: ""
        )
    }

    #Preview("Commit Detail - Missing Commit") {
        CommitDetailPreviewContainer(commit: nil)
            .frame(height: 200)
    }
#endif
