@testable import GitMenuBar
import XCTest

final class ProjectSeverityTests: XCTestCase {
    private func makeSnapshot(
        branchName: String = "main",
        isDetachedHead: Bool = false,
        stagedCount: Int = 0,
        unstagedCount: Int = 0,
        untrackedCount: Int = 0,
        aheadCount: Int = 0,
        behindCount: Int = 0,
        hasUpstream: Bool = true,
        unmergedBranchCount: Int = 0
    ) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/test-project", name: "TestProject"),
            branchName: branchName,
            isDetachedHead: isDetachedHead,
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            lineDiff: .zero,
            aheadCount: aheadCount,
            behindCount: behindCount,
            hasUpstream: hasUpstream,
            lastRefreshedAt: Date(),
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: 0,
            unmergedBranchCount: unmergedBranchCount,
            stashCount: 0,
            lastActivityAt: Date(),
            gitHubStatus: .empty
        )
    }

    func testDivergedOrBehindSeverity() {
        // Behind only
        let behindSnapshot = makeSnapshot(behindCount: 2)
        XCTAssertEqual(behindSnapshot.severity, .divergedOrBehind)

        // Diverged (ahead and behind)
        let divergedSnapshot = makeSnapshot(aheadCount: 3, behindCount: 1)
        XCTAssertEqual(divergedSnapshot.severity, .divergedOrBehind)
    }

    func testUncommittedChangesSeverity() {
        // Staged changes only
        let stagedSnapshot = makeSnapshot(stagedCount: 1)
        XCTAssertEqual(stagedSnapshot.severity, .uncommittedChanges)

        // Unstaged changes only
        let unstagedSnapshot = makeSnapshot(unstagedCount: 2)
        XCTAssertEqual(unstagedSnapshot.severity, .uncommittedChanges)

        // Both staged and unstaged changes
        let bothSnapshot = makeSnapshot(stagedCount: 1, unstagedCount: 1)
        XCTAssertEqual(bothSnapshot.severity, .uncommittedChanges)
    }

    func testUntrackedFilesAloneAreNotAWarning() {
        // Untracked files alone must not produce uncommittedChanges severity or a warning dot
        let untrackedSnapshot = makeSnapshot(untrackedCount: 4)
        XCTAssertNil(untrackedSnapshot.severity)
    }

    func testUnmergedBranchesOnlySeverity() {
        let unmergedSnapshot = makeSnapshot(unmergedBranchCount: 2)
        XCTAssertEqual(unmergedSnapshot.severity, .unmergedOnly)
    }

    func testSeverityPrecedence() {
        // Diverged/behind takes precedence over uncommitted changes
        let behindAndDirtySnapshot = makeSnapshot(stagedCount: 2, behindCount: 1)
        XCTAssertEqual(behindAndDirtySnapshot.severity, .divergedOrBehind)

        // Uncommitted changes take precedence over unmerged branches
        let dirtyAndUnmergedSnapshot = makeSnapshot(stagedCount: 1, unmergedBranchCount: 3)
        XCTAssertEqual(dirtyAndUnmergedSnapshot.severity, .uncommittedChanges)

        // Diverged/behind takes precedence over unmerged branches
        let behindAndUnmergedSnapshot = makeSnapshot(behindCount: 1, unmergedBranchCount: 3)
        XCTAssertEqual(behindAndUnmergedSnapshot.severity, .divergedOrBehind)
    }

    func testCleanSnapshotHasNoSeverity() {
        let cleanSnapshot = makeSnapshot()
        XCTAssertNil(cleanSnapshot.severity)
    }

    func testIsDefaultBranch() {
        XCTAssertTrue(makeSnapshot(branchName: "main").isDefaultBranch)
        XCTAssertTrue(makeSnapshot(branchName: "master").isDefaultBranch)
        XCTAssertFalse(makeSnapshot(branchName: "feature/login").isDefaultBranch)
        XCTAssertFalse(makeSnapshot(branchName: "develop").isDefaultBranch)
        XCTAssertFalse(makeSnapshot(branchName: "main", isDetachedHead: true).isDefaultBranch)
        XCTAssertFalse(makeSnapshot(branchName: "").isDefaultBranch)
    }
}
