@testable import GitMenuBar
import XCTest

final class ProjectSidebarRowViewTests: XCTestCase {
    // MARK: - Column guides

    func testGuidesUseTheWidestTextInEachColumn() {
        let compact = 1284.formatted(.number.notation(.compactName))
        let rows = [
            makeSnapshot(openIssueCount: 9, openPullRequestCount: 2),
            makeSnapshot(openIssueCount: 1284, openPullRequestCount: 34)
        ]

        let guides = ProjectSidebarCountColumns.guides(for: rows)

        XCTAssertEqual(guides.issues, compact)
        XCTAssertEqual(guides.pullRequests, "34")
    }

    func testColumnDisappearsWhenNoVisibleRowShowsIt() {
        let pullRequestOnly = [makeSnapshot(openIssueCount: 0, openPullRequestCount: 1)]
        let pullRequestGuides = ProjectSidebarCountColumns.guides(for: pullRequestOnly)
        XCTAssertNil(pullRequestGuides.issues)
        XCTAssertEqual(pullRequestGuides.pullRequests, "1")

        let localOnly = [
            makeSnapshot(openIssueCount: nil, openPullRequestCount: nil, unavailableReason: .notGitHubRemote)
        ]
        let localGuides = ProjectSidebarCountColumns.guides(for: localOnly)
        XCTAssertNil(localGuides.issues)
        XCTAssertNil(localGuides.pullRequests)
    }

    func testZeroHidesAColumnWhileUnavailableKeepsANeutralGuide() {
        let zero = ProjectSidebarCountColumns.guides(for: [makeSnapshot(openIssueCount: 0, openPullRequestCount: 0)])
        XCTAssertNil(zero.issues)
        XCTAssertNil(zero.pullRequests)

        let unavailable = ProjectSidebarCountColumns.guides(for: [
            makeSnapshot(openIssueCount: nil, openPullRequestCount: nil, unavailableReason: .commandFailed)
        ])
        XCTAssertEqual(unavailable.issues, "—")
        XCTAssertEqual(unavailable.pullRequests, "—")
    }

    // MARK: - Accessibility label

    func testRowLabelKeepsEveryReasonAndBothTotals() {
        let snapshot = makeSnapshot(
            branchName: "feature/editor",
            aheadCount: 2,
            unpushedBranchCount: 3,
            unmergedBranchCount: 3,
            openIssueCount: 1284,
            openPullRequestCount: 34,
            pullRequests: [
                pullRequest(number: 31, headBranch: "feature/editor", reviewState: .changesRequested)
            ]
        )
        let row = ProjectSidebarRowView(
            snapshot: snapshot,
            agentActivities: [],
            showsAgentActivity: true,
            countColumns: .guides(for: [snapshot])
        )

        let label = row.accessibilityLabel
        XCTAssertTrue(label.contains("feature/editor 2 commits to push 2 branches with unpushed commits"))
        XCTAssertTrue(label.contains("PR #31 Changes requested · CI passed"))
        XCTAssertTrue(label.contains("1284 open issues"))
        XCTAssertTrue(label.contains("34 open pull requests"))
    }

    func testRowLabelStatesForeignPullRequestAndUnmergedBranches() {
        let snapshot = makeSnapshot(
            unmergedBranchCount: 3,
            openIssueCount: 0,
            openPullRequestCount: 1,
            pullRequests: [pullRequest(number: 31, headBranch: "feature/editor", reviewState: .changesRequested)]
        )
        let row = ProjectSidebarRowView(
            snapshot: snapshot,
            agentActivities: [],
            showsAgentActivity: true,
            countColumns: .guides(for: [snapshot])
        )

        let label = row.accessibilityLabel
        XCTAssertTrue(label.contains("3 unmerged branches"))
        XCTAssertTrue(label.contains("PR #31 Changes requested · CI passed"))
        XCTAssertTrue(label.contains("1 open pull request"))
    }

    // MARK: - Fixtures

    private func makeSnapshot(
        branchName: String = "main",
        aheadCount: Int = 0,
        unpushedBranchCount: Int = 0,
        unmergedBranchCount: Int = 0,
        openIssueCount: Int? = 0,
        openPullRequestCount: Int? = 0,
        unavailableReason: GitHubStatusUnavailableReason? = nil,
        pullRequests: [GitHubPullRequestSummary] = []
    ) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/project", name: "project"),
            branchName: branchName,
            isDetachedHead: false,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: aheadCount,
            behindCount: 0,
            hasUpstream: true,
            lastRefreshedAt: nil,
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: unpushedBranchCount,
            unmergedBranchCount: unmergedBranchCount,
            stashCount: 0,
            lastActivityAt: nil,
            gitHubStatus: GitHubProjectStatus(
                pullRequests: pullRequests,
                openPullRequestCount: openPullRequestCount,
                openIssueCount: openIssueCount,
                unavailableReason: unavailableReason
            )
        )
    }

    private func pullRequest(
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
