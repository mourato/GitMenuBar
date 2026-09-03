@testable import GitMenuBar
import XCTest

final class RepositoryOverviewSnapshotTests: XCTestCase {
    // MARK: - Known zero vs unavailable

    func testKnownZeroIsDistinctFromUnavailable() {
        let knownZero = RepositoryOverviewSnapshot(
            stagedCount: 0, unstagedCount: 0, untrackedCount: 0,
            addedLineCount: 0, removedLineCount: 0,
            aheadCount: .known(0), behindCount: .known(0),
            branchesWithoutUpstream: .known(0), unpushedBranches: .known(0),
            unmergedBranches: .known(0), stashCount: .known(0),
            historyCount: 0, currentBranch: "main",
            isDetachedHead: false, isLoading: false, lastCheckedAt: nil
        )
        let unavailable = RepositoryOverviewSnapshot(
            stagedCount: 0, unstagedCount: 0, untrackedCount: 0,
            addedLineCount: 0, removedLineCount: 0,
            aheadCount: .known(0), behindCount: .known(0),
            branchesWithoutUpstream: .unavailable, unpushedBranches: .unavailable,
            unmergedBranches: .unavailable, stashCount: .unavailable,
            historyCount: 0, currentBranch: "main",
            isDetachedHead: false, isLoading: false, lastCheckedAt: nil
        )

        XCTAssertNotEqual(knownZero, unavailable)
        XCTAssertEqual(knownZero.stashCount, .known(0))
        XCTAssertEqual(unavailable.stashCount, .unavailable)
    }

    // MARK: - Loading state

    func testLoadingState() {
        let overview = RepositoryOverviewSnapshot(
            stagedCount: 0, unstagedCount: 0, untrackedCount: 0,
            addedLineCount: 0, removedLineCount: 0,
            aheadCount: .known(0), behindCount: .known(0),
            branchesWithoutUpstream: .loading, unpushedBranches: .loading,
            unmergedBranches: .loading, stashCount: .loading,
            historyCount: 0, currentBranch: "main",
            isDetachedHead: false, isLoading: true, lastCheckedAt: nil
        )

        XCTAssertEqual(overview.branchesWithoutUpstream, .loading)
        XCTAssertEqual(overview.stashCount, .loading)
        XCTAssertTrue(overview.isLoading)
    }

    // MARK: - Working tree counts

    func testDirtyWorkingTree() {
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [
                WorkingTreeFile(path: "a.swift", lineDiff: LineDiffStats(added: 4, removed: 1), status: .modified),
                WorkingTreeFile(path: "b.swift", lineDiff: LineDiffStats(added: 2, removed: 0), status: .modified)
            ],
            changedFiles: [
                WorkingTreeFile(path: "c.swift", lineDiff: LineDiffStats(added: 3, removed: 2), status: .modified),
                WorkingTreeFile(path: "d.swift", lineDiff: LineDiffStats(added: 5, removed: 0), status: .untracked)
            ],
            commitCount: 0,
            aheadOfRemote: false,
            behindRemote: false,
            gitBehindCount: 0,
            commitHistory: [],
            currentBranch: "main",
            isDetachedHead: false,
            monitorSnapshot: nil,
            isLoading: false
        )

        XCTAssertEqual(overview.stagedCount, 2)
        XCTAssertEqual(overview.unstagedCount, 1)
        XCTAssertEqual(overview.untrackedCount, 1)
        XCTAssertEqual(overview.totalWorkingTreeCount, 4)
        XCTAssertEqual(overview.addedLineCount, 14)
        XCTAssertEqual(overview.removedLineCount, 3)
        XCTAssertFalse(overview.isCleanWorkingTree)
        XCTAssertNil(overview.lastCheckedAt)
    }

    func testCleanWorkingTree() {
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitCount: 0,
            aheadOfRemote: false,
            behindRemote: false,
            gitBehindCount: 0,
            commitHistory: [],
            currentBranch: "main",
            isDetachedHead: false,
            monitorSnapshot: nil,
            isLoading: false
        )

        XCTAssertTrue(overview.isCleanWorkingTree)
        XCTAssertEqual(overview.totalWorkingTreeCount, 0)
    }

    // MARK: - Ahead / behind

    func testAheadBehindFromMonitorSnapshot() {
        let snapshot = makeMonitorSnapshot(aheadCount: 5, behindCount: 2)
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitCount: 3,
            aheadOfRemote: true,
            behindRemote: true,
            gitBehindCount: 1,
            commitHistory: [],
            currentBranch: "feature",
            isDetachedHead: false,
            monitorSnapshot: snapshot,
            isLoading: false
        )

        XCTAssertEqual(overview.aheadCount, .known(5))
        XCTAssertEqual(overview.behindCount, .known(2))
        XCTAssertNotNil(overview.lastCheckedAt)
    }

    func testAheadBehindFallsBackToGitManager() {
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitCount: 3,
            aheadOfRemote: true,
            behindRemote: false,
            gitBehindCount: 0,
            commitHistory: [],
            currentBranch: "feature",
            isDetachedHead: false,
            monitorSnapshot: nil,
            isLoading: false
        )

        XCTAssertEqual(overview.aheadCount, .known(3))
        XCTAssertEqual(overview.behindCount, .known(0))
    }

    // MARK: - Detached HEAD

    func testDetachedHead() {
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitCount: 0,
            aheadOfRemote: false,
            behindRemote: false,
            gitBehindCount: 0,
            commitHistory: [],
            currentBranch: "",
            isDetachedHead: true,
            monitorSnapshot: nil,
            isLoading: false
        )

        XCTAssertTrue(overview.isDetachedHead)
        XCTAssertNil(overview.currentBranch)
    }

    // MARK: - Branch and stash from monitor

    func testBranchAndStashFromMonitor() {
        let snapshot = makeMonitorSnapshot(
            branchesWithoutUpstreamCount: 2,
            unpushedBranchCount: 1,
            unmergedBranchCount: 3,
            stashCount: 4
        )
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitCount: 0,
            aheadOfRemote: false,
            behindRemote: false,
            gitBehindCount: 0,
            commitHistory: [],
            currentBranch: "main",
            isDetachedHead: false,
            monitorSnapshot: snapshot,
            isLoading: false
        )

        XCTAssertEqual(overview.branchesWithoutUpstream, .known(2))
        XCTAssertEqual(overview.unpushedBranches, .known(1))
        XCTAssertEqual(overview.unmergedBranches, .known(3))
        XCTAssertEqual(overview.stashCount, .known(4))
    }

    func testNoMonitorSnapshotWhileLoadingShowsLoading() {
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitCount: 0,
            aheadOfRemote: false,
            behindRemote: false,
            gitBehindCount: 0,
            commitHistory: [],
            currentBranch: "main",
            isDetachedHead: false,
            monitorSnapshot: nil,
            isLoading: true
        )

        XCTAssertEqual(overview.branchesWithoutUpstream, .loading)
        XCTAssertEqual(overview.stashCount, .loading)
    }

    func testNoMonitorSnapshotNotLoadingShowsUnavailable() {
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitCount: 0,
            aheadOfRemote: false,
            behindRemote: false,
            gitBehindCount: 0,
            commitHistory: [],
            currentBranch: "main",
            isDetachedHead: false,
            monitorSnapshot: nil,
            isLoading: false
        )

        XCTAssertEqual(overview.branchesWithoutUpstream, .unavailable)
        XCTAssertEqual(overview.stashCount, .unavailable)
    }

    // MARK: - History count

    func testHistoryCountReflectsCommitHistory() {
        let commits = (0 ..< 5).map { index in
            Commit(
                id: "hash\(index)", shortHash: "h\(index)", subject: "Commit \(index)", body: "",
                authorName: "A", authorEmail: "a@b.c", committedAt: Date(),
                stats: CommitStats(filesChanged: 0, insertions: 0, deletions: 0),
                changedFiles: []
            )
        }
        let overview = RepositoryOverviewSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitCount: 0,
            aheadOfRemote: false,
            behindRemote: false,
            gitBehindCount: 0,
            commitHistory: commits,
            currentBranch: "main",
            isDetachedHead: false,
            monitorSnapshot: nil,
            isLoading: false
        )

        XCTAssertEqual(overview.historyCount, 5)
    }

    // MARK: - Helpers

    private func makeMonitorSnapshot(
        aheadCount: Int = 0,
        behindCount: Int = 0,
        branchesWithoutUpstreamCount: Int = 0,
        unpushedBranchCount: Int = 0,
        unmergedBranchCount: Int = 0,
        stashCount: Int = 0
    ) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/repo", name: "Repo"),
            branchName: "main",
            isDetachedHead: false,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: aheadCount,
            behindCount: behindCount,
            hasUpstream: true,
            lastRefreshedAt: Date(),
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: branchesWithoutUpstreamCount,
            unpushedBranchCount: unpushedBranchCount,
            unmergedBranchCount: unmergedBranchCount,
            stashCount: stashCount,
            lastActivityAt: nil,
            pullRequests: []
        )
    }
}
