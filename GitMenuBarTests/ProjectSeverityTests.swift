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
        unmergedBranchCount: Int = 0,
        unpushedBranchCount: Int = 0,
        pullRequests: [GitHubPullRequestSummary] = [],
        lastErrorDescription: String? = nil
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
            lastErrorDescription: lastErrorDescription,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: unpushedBranchCount,
            unmergedBranchCount: unmergedBranchCount,
            stashCount: 0,
            lastActivityAt: Date(),
            gitHubStatus: GitHubProjectStatus(
                pullRequests: pullRequests, openPullRequestCount: pullRequests.count,
                openIssueCount: 0, unavailableReason: nil
            )
        )
    }

    func testBehindOrDivergedIsCritical() {
        let behindSnapshot = makeSnapshot(behindCount: 2)
        XCTAssertEqual(behindSnapshot.severity, .critical)

        let divergedSnapshot = makeSnapshot(aheadCount: 3, behindCount: 1)
        XCTAssertEqual(divergedSnapshot.severity, .critical)
    }

    func testUncommittedChangesSeverity() {
        let stagedSnapshot = makeSnapshot(stagedCount: 1)
        XCTAssertEqual(stagedSnapshot.severity, .localWork)

        let unstagedSnapshot = makeSnapshot(unstagedCount: 2)
        XCTAssertEqual(unstagedSnapshot.severity, .localWork)

        let bothSnapshot = makeSnapshot(stagedCount: 1, unstagedCount: 1)
        XCTAssertEqual(bothSnapshot.severity, .localWork)
    }

    func testUntrackedFilesAloneAreNotAWarning() {
        let untrackedSnapshot = makeSnapshot(untrackedCount: 4)
        XCTAssertNil(untrackedSnapshot.severity)
    }

    func testCommitsToPushAreLocalWork() {
        XCTAssertEqual(makeSnapshot(aheadCount: 2).severity, .localWork)
        XCTAssertEqual(makeSnapshot(unpushedBranchCount: 2).severity, .localWork)
        XCTAssertEqual(makeSnapshot(behindCount: 1, unpushedBranchCount: 2).severity, .critical)
    }

    func testUnmergedBranchesAloneShowNoDot() {
        XCTAssertNil(makeSnapshot(unmergedBranchCount: 2).severity)
    }

    private let failingPullRequest = GitHubPullRequestSummary(
        number: 1, title: "Change", headBranch: "feature/change", isDraft: false,
        reviewState: .reviewRequired, checksState: .failing, url: "https://github.com/example/project/pull/1"
    )

    func testFailingChecksAreCriticalAndNamed() {
        let snapshot = makeSnapshot(unmergedBranchCount: 1, pullRequests: [failingPullRequest])
        XCTAssertEqual(snapshot.severity, .critical)
        XCTAssertTrue(snapshot.summaryFacts.first?.hasSuffix("CI failing") == true)
    }

    func testFailingChecksWinOverUncommittedChanges() {
        XCTAssertEqual(makeSnapshot(stagedCount: 1, pullRequests: [failingPullRequest]).severity, .critical)
    }

    func testRefreshErrorShowsNoDot() {
        XCTAssertNil(makeSnapshot(behindCount: 2, lastErrorDescription: "failed").severity)
    }

    func testSeverityPrecedence() {
        let behindAndDirtySnapshot = makeSnapshot(stagedCount: 2, behindCount: 1)
        XCTAssertEqual(behindAndDirtySnapshot.severity, .critical)

        let dirtyAndUnmergedSnapshot = makeSnapshot(stagedCount: 1, unmergedBranchCount: 3)
        XCTAssertEqual(dirtyAndUnmergedSnapshot.severity, .localWork)

        let behindAndUnmergedSnapshot = makeSnapshot(behindCount: 1, unmergedBranchCount: 3)
        XCTAssertEqual(behindAndUnmergedSnapshot.severity, .critical)
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
