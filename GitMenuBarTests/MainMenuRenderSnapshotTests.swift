@testable import GitMenuBar
import XCTest

final class MainMenuRenderSnapshotTests: XCTestCase {
    func testBuildUsesCustomProjectNameForCurrentRepository() {
        let snapshot = MainMenuRenderSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitHistory: [],
            currentHash: "",
            remoteUrl: "",
            availableBranches: [],
            currentBranch: "",
            isStagedSectionCollapsed: false,
            isUnstagedSectionCollapsed: false,
            isHistorySectionCollapsed: false,
            recentProjects: [
                ProjectReference(path: "/tmp/worktrees/client-a", name: "Client A")
            ],
            currentRepoPath: "/tmp/worktrees/../worktrees/client-a",
            isCommitInFuture: { _ in false }
        )

        XCTAssertEqual(snapshot.currentProjectName, "Client A")
    }

    func testBuildFallsBackToFolderNameWhenCurrentProjectIsMissing() {
        let snapshot = MainMenuRenderSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitHistory: [],
            currentHash: "",
            remoteUrl: "",
            availableBranches: [],
            currentBranch: "",
            isStagedSectionCollapsed: false,
            isUnstagedSectionCollapsed: false,
            isHistorySectionCollapsed: false,
            recentProjects: [],
            currentRepoPath: "/tmp/worktrees/client-a",
            isCommitInFuture: { _ in false }
        )

        XCTAssertEqual(snapshot.currentProjectName, "client-a")
    }

    func testBuildSuppressesRepositoryRowsWhenCurrentRepositoryIsEmpty() {
        let snapshot = MainMenuRenderSnapshot.build(
            stagedFiles: [
                WorkingTreeFile(path: "staged.swift", lineDiff: .zero, status: .modified)
            ],
            changedFiles: [
                WorkingTreeFile(path: "changed.swift", lineDiff: .zero, status: .modified)
            ],
            commitHistory: [
                Commit(
                    id: "abc123",
                    shortHash: "abc123",
                    subject: "Initial commit",
                    body: "",
                    authorName: "Author",
                    authorEmail: "author@example.com",
                    committedAt: Date(),
                    stats: CommitStats(filesChanged: 0, insertions: 0, deletions: 0),
                    changedFiles: []
                )
            ],
            currentHash: "abc123",
            remoteUrl: "",
            availableBranches: ["main"],
            currentBranch: "main",
            isStagedSectionCollapsed: false,
            isUnstagedSectionCollapsed: false,
            isHistorySectionCollapsed: false,
            recentProjects: [
                ProjectReference(path: "/tmp/worktrees/client-a", name: "Client A")
            ],
            currentRepoPath: "",
            isCommitInFuture: { _ in false }
        )

        XCTAssertEqual(snapshot.currentProjectName, "Select Project")
        XCTAssertTrue(snapshot.stagedRowAdapters.isEmpty)
        XCTAssertTrue(snapshot.unstagedRowAdapters.isEmpty)
        XCTAssertTrue(snapshot.historyRowAdapters.isEmpty)
        XCTAssertTrue(snapshot.historySections.isEmpty)
        XCTAssertTrue(snapshot.keyboardSelectableItems.isEmpty)
        XCTAssertTrue(snapshot.branchMenuRows.isEmpty)
    }

    func testBuildIncludesOverviewInSnapshot() {
        let overview = RepositoryOverviewSnapshot(
            stagedCount: 2, unstagedCount: 1, untrackedCount: 0,
            addedLineCount: 0, removedLineCount: 0,
            aheadCount: .known(3), behindCount: .known(0),
            branchesWithoutUpstream: .known(1), unpushedBranches: .known(0),
            unmergedBranches: .known(0), stashCount: .known(2),
            historyCount: 10, currentBranch: "main",
            isDetachedHead: false, isLoading: false, lastCheckedAt: nil
        )
        let snapshot = MainMenuRenderSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitHistory: [],
            currentHash: "",
            remoteUrl: "",
            availableBranches: [],
            currentBranch: "main",
            isStagedSectionCollapsed: false,
            isUnstagedSectionCollapsed: false,
            isHistorySectionCollapsed: false,
            recentProjects: [],
            currentRepoPath: "/tmp/repo",
            isCommitInFuture: { _ in false },
            overview: overview
        )

        XCTAssertEqual(snapshot.overview, overview)
        XCTAssertEqual(snapshot.overview.stagedCount, 2)
        XCTAssertEqual(snapshot.overview.aheadCount, .known(3))
    }

    func testDefaultOverviewIsEmpty() {
        let snapshot = MainMenuRenderSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitHistory: [],
            currentHash: "",
            remoteUrl: "",
            availableBranches: [],
            currentBranch: "",
            isStagedSectionCollapsed: false,
            isUnstagedSectionCollapsed: false,
            isHistorySectionCollapsed: false,
            recentProjects: [],
            currentRepoPath: "",
            isCommitInFuture: { _ in false }
        )

        XCTAssertEqual(snapshot.overview, RepositoryOverviewSnapshot.empty)
    }
}
