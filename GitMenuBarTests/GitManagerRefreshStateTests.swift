@testable import GitMenuBar
import XCTest

@MainActor
final class GitManagerRefreshStateTests: XCTestCase {
    func testResetSelectedRepositoryStateClearsDisplayedRepositoryData() {
        let manager = GitManager(repositoryPathOverride: "/tmp/repository")
        let file = WorkingTreeFile(path: "README.md", lineDiff: LineDiffStats(added: 1, removed: 0), status: .modified)

        manager.uncommittedFiles = [file.path]
        manager.stagedFiles = [file]
        manager.changedFiles = [file]
        manager.currentBranch = "feature"
        manager.isAheadOfRemote = true
        manager.isDetachedHead = true
        manager.remoteUrl = "https://example.com/repository.git"
        manager.commitHistory = [Commit(
            id: "abc123",
            shortHash: "abc123",
            subject: "Commit",
            body: "",
            authorName: "Author",
            authorEmail: "author@example.com",
            committedAt: Date.distantPast,
            stats: CommitStats(filesChanged: 1, insertions: 1, deletions: 0),
            changedFiles: []
        )]
        manager.currentHash = "abc123"
        manager.lastActiveBranch = "feature"
        manager.defaultBranchName = "develop"
        manager.worktreeSnapshot = GitWorktreeSnapshot(
            repositoryPath: "/tmp/repository",
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "analysis",
            worktrees: [],
            branches: []
        )
        manager.availableBranches = ["feature"]
        manager.branchInfos = [BranchInfo(
            name: "feature",
            isLocal: true,
            isRemote: false,
            isCurrent: true,
            trackingStatus: .unknown,
            lastCommitDate: Date.distantPast
        )]
        manager.isRemoteAhead = true
        manager.isBehindRemote = true
        manager.remoteBranchName = "origin/feature"
        manager.behindCount = 2
        manager.isPrivate = true
        manager.commitCount = 3

        manager.resetSelectedRepositoryState()

        XCTAssertTrue(manager.uncommittedFiles.isEmpty)
        XCTAssertTrue(manager.stagedFiles.isEmpty)
        XCTAssertTrue(manager.changedFiles.isEmpty)
        XCTAssertTrue(manager.commitHistory.isEmpty)
        XCTAssertEqual(manager.currentBranch, "")
        XCTAssertEqual(manager.currentHash, "")
        XCTAssertFalse(manager.isDetachedHead)
        XCTAssertEqual(manager.lastActiveBranch, "")
        XCTAssertEqual(manager.defaultBranchName, "")
        XCTAssertEqual(manager.remoteUrl, "")
        XCTAssertFalse(manager.isAheadOfRemote)
        XCTAssertFalse(manager.isRemoteAhead)
        XCTAssertFalse(manager.isBehindRemote)
        XCTAssertEqual(manager.remoteBranchName, "")
        XCTAssertEqual(manager.behindCount, 0)
        XCTAssertTrue(manager.availableBranches.isEmpty)
        XCTAssertTrue(manager.branchInfos.isEmpty)
        XCTAssertNil(manager.worktreeSnapshot)
        XCTAssertFalse(manager.isPrivate)
        XCTAssertEqual(manager.commitCount, 0)
    }
}
