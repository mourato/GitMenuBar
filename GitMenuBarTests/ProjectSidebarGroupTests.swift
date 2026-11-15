@testable import GitMenuBar
import XCTest

final class ProjectSidebarGroupTests: XCTestCase {
    func testUnmergedBranchesAloneAreInReview() {
        XCTAssertEqual(snapshot(unmergedBranchCount: 4).sidebarGroup, .inReview)
    }

    func testOpenPullRequestWithPassingChecksIsInReview() {
        XCTAssertEqual(snapshot(pullRequests: [pullRequest(checks: .passed)]).sidebarGroup, .inReview)
    }

    func testFailingChecksNeedAction() {
        XCTAssertEqual(
            snapshot(unmergedBranchCount: 1, pullRequests: [pullRequest(checks: .failing)]).sidebarGroup,
            .needsAction
        )
    }

    func testLocalWorkNeedsAction() {
        XCTAssertEqual(snapshot(stagedCount: 1).sidebarGroup, .needsAction)
        XCTAssertEqual(snapshot(aheadCount: 2).sidebarGroup, .needsAction)
        XCTAssertEqual(snapshot(unpushedBranchCount: 1).sidebarGroup, .needsAction)
    }

    func testBehindNeedsAction() {
        XCTAssertEqual(snapshot(behindCount: 3).sidebarGroup, .needsAction)
    }

    func testNothingPendingIsUpToDate() {
        XCTAssertEqual(snapshot().sidebarGroup, .upToDate)
    }

    func testRefreshErrorIsUnavailable() {
        XCTAssertEqual(snapshot(stagedCount: 1, error: "failed").sidebarGroup, .unavailable)
    }

    private func pullRequest(checks: GitHubChecksState) -> GitHubPullRequestSummary {
        GitHubPullRequestSummary(
            number: 1, title: "Change", headBranch: "feature/change", isDraft: false,
            reviewState: .reviewRequired, checksState: checks, url: "https://github.com/example/project/pull/1"
        )
    }

    private func snapshot(
        stagedCount: Int = 0,
        aheadCount: Int = 0,
        behindCount: Int = 0,
        unpushedBranchCount: Int = 0,
        unmergedBranchCount: Int = 0,
        pullRequests: [GitHubPullRequestSummary] = [],
        error: String? = nil
    ) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/project"), branchName: "main", isDetachedHead: false,
            stagedCount: stagedCount, unstagedCount: 0, untrackedCount: 0, lineDiff: .zero,
            aheadCount: aheadCount, behindCount: behindCount, hasUpstream: true, lastRefreshedAt: Date(),
            lastErrorDescription: error, branchesWithoutUpstreamCount: 0, unpushedBranchCount: unpushedBranchCount,
            unmergedBranchCount: unmergedBranchCount, stashCount: 0, lastActivityAt: nil,
            gitHubStatus: GitHubProjectStatus(
                pullRequests: pullRequests, openPullRequestCount: pullRequests.count,
                openIssueCount: 0, unavailableReason: nil
            )
        )
    }
}
