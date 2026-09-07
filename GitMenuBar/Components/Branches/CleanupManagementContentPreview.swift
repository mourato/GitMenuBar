import SwiftUI

#Preview("Cleanup mode") {
    CleanupManagementContentView(
        snapshot: GitWorktreeSnapshot(
            repositoryPath: "/Users/example/repo",
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "Local Git refs; remote status is based on the last fetch.",
            worktrees: [],
            branches: [
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/merged", headHash: "1234", isRemote: false),
                    status: .mergedIntoDefault,
                    worktreePath: nil
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/active", headHash: "5678", isRemote: false),
                    status: .current,
                    worktreePath: nil
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/wip", headHash: "9abc", isRemote: false),
                    status: .notMerged,
                    worktreePath: nil
                )
            ]
        ),
        errorMessage: nil,
        query: "",
        selectedIDs: .constant([]),
        onDismissError: {},
        onReveal: { _ in },
        onCopyPath: { _ in },
        onForceRemove: { _ in },
        onCleanUnit: { _ in }
    )
    .frame(width: 560)
}
