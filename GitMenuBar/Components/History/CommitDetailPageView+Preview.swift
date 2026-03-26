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
}

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
    .environmentObject(
        GitHubAuthManager(
            tokenStore: InMemoryGitHubTokenStore(),
            preloadStoredToken: false
        )
    )
    .frame(width: 400, height: 580)
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
    .environmentObject(
        GitHubAuthManager(
            tokenStore: InMemoryGitHubTokenStore(),
            preloadStoredToken: false
        )
    )
    .padding()
    .frame(width: 400)
}
