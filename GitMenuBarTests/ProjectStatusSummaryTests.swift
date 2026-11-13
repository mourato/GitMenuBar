@testable import GitMenuBar
import XCTest

final class ProjectStatusSummaryTests: XCTestCase {
    // MARK: - Needs Attention always states a reason

    func testOpenPullRequestFromAnotherBranchExplainsNeedsAttention() {
        // GitHub detail list has a pull request, but it is not the current
        // branch's own: the summary used to fall through to "Up to date".
        let snapshot = makeSnapshot(
            pullRequests: [
                Self.pullRequest(number: 31, headBranch: "feature/editor", reviewState: .changesRequested)
            ]
        )

        XCTAssertEqual(snapshot.classification, .needsAttention)
        XCTAssertEqual(snapshot.statusSummary, "PR #31 Changes requested · CI passed")
    }

    func testOtherUnpushedBranchesExplainNeedsAttention() {
        let snapshot = makeSnapshot(unpushedBranchCount: 2)

        XCTAssertEqual(snapshot.classification, .needsAttention)
        XCTAssertEqual(snapshot.statusSummary, "2 branches with unpushed commits")
    }

    func testCurrentBranchDoesNotRepeatTheUnpushedBranchReason() {
        // The current branch is already stated as commits to push.
        let snapshot = makeSnapshot(branchName: "feature/editor", aheadCount: 2, unpushedBranchCount: 1)

        XCTAssertEqual(snapshot.statusSummary, "feature/editor 2 commits to push")
    }

    func testUnpushedBranchesBeyondTheCurrentBranchStayInTheSummary() {
        let snapshot = makeSnapshot(branchName: "feature/editor", aheadCount: 2, unpushedBranchCount: 3)

        XCTAssertEqual(
            snapshot.statusSummary,
            "feature/editor 2 commits to push 2 branches with unpushed commits"
        )
    }

    func testForeignPullRequestJoinsTheUnmergedReason() {
        let snapshot = makeSnapshot(
            unmergedBranchCount: 3,
            pullRequests: [
                Self.pullRequest(number: 31, headBranch: "feature/editor", reviewState: .changesRequested)
            ]
        )

        XCTAssertEqual(snapshot.statusSummary, "3 unmerged branches PR #31 Changes requested · CI passed")
    }

    func testAheadWithoutAnUpstreamFlagStillStatesTheReason() {
        // The model permits this combination even though the porcelain parser
        // does not produce it; the summary must not fall through to Up to date.
        let snapshot = makeSnapshot(aheadCount: 2, hasUpstream: false)

        XCTAssertEqual(snapshot.classification, .needsAttention)
        XCTAssertEqual(snapshot.statusSummary, "2 commits to push")
    }

    func testBehindSummary() {
        XCTAssertEqual(makeSnapshot(behindCount: 2).statusSummary, "2 commits behind")
    }

    func testDetachedSummary() {
        XCTAssertEqual(makeSnapshot(branchName: "", isDetachedHead: true).statusSummary, "Detached")
    }

    func testStaleReasonAppendsToTheSummary() {
        let snapshot = makeSnapshot(
            unmergedBranchCount: 3,
            lastActivityAt: Date(timeIntervalSinceNow: -ProjectStatusSnapshot.staleThreshold - 60)
        )

        XCTAssertTrue(snapshot.isStale)
        XCTAssertEqual(snapshot.statusSummary, "3 unmerged branches Stale work")
    }

    func testCurrentBranchPullRequestKeepsItsStatusInTheSummary() {
        let snapshot = makeSnapshot(
            branchName: "feature/editor",
            pullRequests: [
                Self.pullRequest(number: 31, headBranch: "feature/editor", reviewState: .reviewRequired)
            ]
        )

        XCTAssertEqual(snapshot.statusSummary, "feature/editor PR #31 Review required · CI passed")
    }

    // MARK: - Wording

    func testUnmergedBranchWordingUsesSingularAndPlural() {
        XCTAssertEqual(makeSnapshot(unmergedBranchCount: 1).statusSummary, "1 unmerged branch")
        XCTAssertEqual(makeSnapshot(unmergedBranchCount: 8).statusSummary, "8 unmerged branches")
    }

    func testBranchUpstreamAndUnmergedStateCombine() {
        let snapshot = makeSnapshot(
            branchName: "feature/cleanup",
            aheadCount: 2,
            unmergedBranchCount: 3
        )

        XCTAssertEqual(snapshot.statusSummary, "feature/cleanup 2 commits to push 3 unmerged branches")
    }

    // MARK: - Clean rows keep the old summaries

    func testCleanDefaultBranchReadsUpToDate() {
        let snapshot = makeSnapshot()

        XCTAssertEqual(snapshot.classification, .clean)
        XCTAssertEqual(snapshot.statusSummary, "Up to date")
    }

    func testWorkingTreeChangesStayTheReasonWhenNothingElseIsStated() {
        let snapshot = makeSnapshot(stagedCount: 1)

        XCTAssertEqual(snapshot.classification, .needsAttention)
        XCTAssertEqual(snapshot.statusSummary, "Uncommitted changes")
    }

    func testUnavailableRowReadsUnavailable() {
        let snapshot = makeSnapshot(lastErrorDescription: "git status failed")

        XCTAssertEqual(snapshot.classification, .unavailable)
        XCTAssertEqual(snapshot.statusSummary, "Unavailable")
    }

    // MARK: - Fixtures

    private func makeSnapshot(
        branchName: String = "main",
        isDetachedHead: Bool = false,
        stagedCount: Int = 0,
        aheadCount: Int = 0,
        behindCount: Int = 0,
        hasUpstream: Bool = true,
        unpushedBranchCount: Int = 0,
        unmergedBranchCount: Int = 0,
        pullRequests: [GitHubPullRequestSummary] = [],
        lastActivityAt: Date? = nil,
        lastErrorDescription: String? = nil
    ) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/project", name: "project"),
            branchName: branchName,
            isDetachedHead: isDetachedHead,
            stagedCount: stagedCount,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: aheadCount,
            behindCount: behindCount,
            hasUpstream: hasUpstream,
            lastRefreshedAt: nil,
            lastErrorDescription: lastErrorDescription,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: unpushedBranchCount,
            unmergedBranchCount: unmergedBranchCount,
            stashCount: 0,
            lastActivityAt: lastActivityAt,
            gitHubStatus: GitHubProjectStatus(
                pullRequests: pullRequests,
                openPullRequestCount: pullRequests.isEmpty ? 0 : pullRequests.count,
                openIssueCount: 0,
                unavailableReason: nil
            )
        )
    }

    private static func pullRequest(
        number: Int,
        headBranch: String,
        reviewState: GitHubPullRequestReviewState
    ) -> GitHubPullRequestSummary {
        GitHubPullRequestSummary(
            number: number,
            title: "Pull request \(number)",
            headBranch: headBranch,
            isDraft: false,
            reviewState: reviewState,
            checksState: .passed,
            url: "https://github.com/example/project/pull/\(number)"
        )
    }
}
