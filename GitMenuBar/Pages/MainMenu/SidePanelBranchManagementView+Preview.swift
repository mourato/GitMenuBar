import SwiftUI

/// Seeds the harness `GitManager` so previews render real branch rows, cleanup badges, and filter counts.
private struct SidePanelPreviewSeed: View {
    @Environment(GitManager.self) private var gitManager
    let initialFilter: BranchFilter
    let initialQuery: String

    var body: some View {
        SidePanelBranchManagementView(
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in },
            onCreateBranch: {},
            onRenameBranch: { _ in },
            initialFilter: initialFilter,
            initialQuery: initialQuery
        )
        .onAppear {
            SidePanelPreviewFixture.apply(to: gitManager)
        }
    }
}

@MainActor
private enum SidePanelPreviewFixture {
    static func apply(to gitManager: GitManager) {
        let now = Date()
        let branches = [
            BranchInfo(
                name: "main",
                isLocal: true,
                isRemote: false,
                isCurrent: true,
                trackingStatus: .upToDate,
                lastCommitDate: now.addingTimeInterval(-3600)
            ),
            BranchInfo(
                name: "feature/merged-one",
                isLocal: true,
                isRemote: false,
                isCurrent: false,
                trackingStatus: .noRemote,
                lastCommitDate: now.addingTimeInterval(-86400)
            ),
            BranchInfo(
                name: "feature/merged-two",
                isLocal: true,
                isRemote: false,
                isCurrent: false,
                trackingStatus: .noRemote,
                lastCommitDate: now.addingTimeInterval(-172_800)
            ),
            BranchInfo(
                name: "feature/dirty-wip",
                isLocal: true,
                isRemote: false,
                isCurrent: false,
                trackingStatus: .ahead(2),
                lastCommitDate: now.addingTimeInterval(-1800)
            ),
            BranchInfo(
                name: "feature/stale-experiment",
                isLocal: true,
                isRemote: false,
                isCurrent: false,
                trackingStatus: .noRemote,
                lastCommitDate: now.addingTimeInterval(-30 * 86400)
            ),
            BranchInfo(
                name: "feature/checkout-flow-with-very-long-descriptive-suffix-for-truncation-check",
                isLocal: true,
                isRemote: false,
                isCurrent: false,
                trackingStatus: .behind(3),
                lastCommitDate: now.addingTimeInterval(-259_200)
            ),
            BranchInfo(
                name: "feature/remote-only",
                isLocal: false,
                isRemote: true,
                isCurrent: false,
                trackingStatus: .noRemote,
                lastCommitDate: now.addingTimeInterval(-86400),
                remoteName: "origin"
            ),
            BranchInfo(
                name: "release/1.2",
                isLocal: false,
                isRemote: true,
                isCurrent: false,
                trackingStatus: .noRemote,
                lastCommitDate: now.addingTimeInterval(-604_800),
                remoteName: "origin"
            ),
            BranchInfo(
                name: "release/1.3",
                isLocal: false,
                isRemote: true,
                isCurrent: false,
                trackingStatus: .noRemote,
                lastCommitDate: now.addingTimeInterval(-259_200),
                remoteName: "origin"
            )
        ]

        let dirtyWorktree = GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(path: "/tmp/wt-dirty-wip", headHash: "hash-dirty", branchName: "feature/dirty-wip"),
            status: .dirty
        )
        let mergedBranch: (String) -> GitBranchCleanupInfo = { name in
            GitBranchCleanupInfo(
                reference: GitBranchReference(name: name, headHash: "hash-\(name)", isRemote: false),
                status: .mergedIntoDefault,
                worktreePath: nil
            )
        }
        let mergedOne = GitCleanupUnit(
            repositoryIdentity: "preview-repo",
            branch: mergedBranch("feature/merged-one"),
            worktree: nil,
            mode: .safe
        )
        let mergedTwo = GitCleanupUnit(
            repositoryIdentity: "preview-repo",
            branch: mergedBranch("feature/merged-two"),
            worktree: nil,
            mode: .safe
        )
        let dirtyUnit = GitCleanupUnit(
            repositoryIdentity: "preview-repo",
            branch: GitBranchCleanupInfo(
                reference: GitBranchReference(name: "feature/dirty-wip", headHash: "hash-dirty", isRemote: false),
                status: .notMerged,
                worktreePath: dirtyWorktree.worktree.path
            ),
            worktree: dirtyWorktree,
            mode: .safe
        )
        let units = [mergedOne, mergedTwo, dirtyUnit]
        let snapshot = GitWorktreeSnapshot(
            repositoryPath: "/tmp/preview-repo",
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "preview snapshot",
            worktrees: [dirtyWorktree],
            branches: units.map(\.branch),
            repositoryIdentity: "preview-repo",
            cleanupUnits: units,
            managementUnits: units
        )

        gitManager.branchInfos = branches
        gitManager.defaultBranchName = "main"
        gitManager.worktreeSnapshot = snapshot
    }
}

#Preview("Side Panel Branch Management") {
    MainMenuPreviewHarness {
        SidePanelPreviewSeed(initialFilter: .all, initialQuery: "")
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 640)
}

#Preview("Side Panel · Mergeable Filter") {
    MainMenuPreviewHarness {
        SidePanelPreviewSeed(initialFilter: .mergeable, initialQuery: "")
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 640)
}

#Preview("Side Panel · Empty State") {
    MainMenuPreviewHarness {
        SidePanelPreviewSeed(initialFilter: .all, initialQuery: "no-such-branch")
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 640)
}
