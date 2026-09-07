import SwiftUI

#Preview("Cleanup states") {
    let pairedPath = "/Users/example/feature-ui"
    let dirtyPath = "/Users/example/dirty"
    let monitoredPath = "/Users/example/monitored"
    let lockedPath = "/Users/example/locked"
    let detachedPath = "/Users/example/detached"
    let worktrees = [
        GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(
                path: pairedPath,
                headHash: "5678",
                branchName: "feature/ui",
                workingTreeState: .clean
            ),
            status: .eligible
        ),
        GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(
                path: dirtyPath,
                headHash: "9abc",
                branchName: "feature/wip",
                workingTreeState: .dirty
            ),
            status: .dirty
        ),
        GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(
                path: monitoredPath,
                headHash: "def0",
                branchName: "feature/monitored",
                workingTreeState: .clean
            ),
            status: .unknown(reason: "Worktree is monitored as a project and protected from cleanup.")
        ),
        GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(
                path: lockedPath,
                headHash: "1111",
                branchName: "feature/locked",
                workingTreeState: .clean
            ),
            status: .locked(reason: "Maintenance lock")
        ),
        GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(
                path: detachedPath,
                headHash: "2222",
                branchName: nil,
                workingTreeState: .clean
            ),
            status: .detached
        )
    ]
    CleanupManagementContentView(
        snapshot: GitWorktreeSnapshot(
            repositoryPath: "/Users/example/repo",
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "Local Git refs; remote status is based on the last fetch.",
            worktrees: worktrees,
            branches: [
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/merged", headHash: "1234", isRemote: false),
                    status: .mergedIntoDefault,
                    worktreePath: nil
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/ui", headHash: "5678", isRemote: false),
                    status: .checkedOutElsewhere(path: pairedPath),
                    worktreePath: pairedPath,
                    isMergedIntoDefaultHint: true
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/wip", headHash: "9abc", isRemote: false),
                    status: .checkedOutElsewhere(path: dirtyPath),
                    worktreePath: dirtyPath
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/monitored", headHash: "def0", isRemote: false),
                    status: .checkedOutElsewhere(path: monitoredPath),
                    worktreePath: monitoredPath
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/locked", headHash: "1111", isRemote: false),
                    status: .checkedOutElsewhere(path: lockedPath),
                    worktreePath: lockedPath
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/unknown", headHash: "3333", isRemote: false),
                    status: .unknown(reason: "Merge status is unavailable."),
                    worktreePath: nil
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/unmerged", headHash: "4444", isRemote: false),
                    status: .notMerged,
                    worktreePath: nil
                ),
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "main", headHash: "0000", isRemote: false),
                    status: .protected,
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
        onCleanUnit: { _ in },
        onDeleteBranch: { _ in },
        onRemoveWorktree: { _ in }
    )
    .frame(width: 560, height: 720)
}
