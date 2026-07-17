import SwiftUI

#Preview("Worktree mode with data") {
    WorktreeManagementContentView(
        snapshot: GitWorktreeSnapshot(
            repositoryPath: "/Users/example/repo",
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "Local Git refs; remote status is based on the last fetch.",
            worktrees: [
                GitWorktreeCleanupInfo(
                    worktree: GitWorktreeInfo(
                        path: "/Users/example/feature",
                        headHash: "1234567890",
                        branchName: "feature/ui",
                        workingTreeState: .clean
                    ),
                    status: .eligible
                )
            ],
            branches: []
        ),
        errorMessage: nil,
        query: "",
        onReveal: { _ in },
        onCopyPath: { _ in },
        onDismissError: {}
    )
    .frame(width: 560)
}
