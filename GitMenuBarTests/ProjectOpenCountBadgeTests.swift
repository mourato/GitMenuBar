@testable import GitMenuBar
import XCTest

final class ProjectOpenCountBadgeTests: XCTestCase {
    func testKnownZeroHidesBadgesWhileUnknownStatesRemainVisible() {
        let zero = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: [], openPullRequestCount: 0, openIssueCount: 0, unavailableReason: nil
            )
        )
        XCTAssertNil(zero.openIssueBadge)
        XCTAssertNil(zero.openPullRequestBadge)

        let unread = makeSnapshot(gitHubStatus: .empty)
        XCTAssertEqual(unread.openIssueBadge, .pending)
        XCTAssertEqual(unread.openPullRequestBadge, .pending)
        XCTAssertEqual(unread.openIssueBadge?.text, "—")
        XCTAssertEqual(unread.openIssueBadge?.accessibilityDescription(singularNoun: "issue"), "Issue count loading")

        let failed = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: [], openPullRequestCount: nil, openIssueCount: nil,
                unavailableReason: .commandFailed
            )
        )
        XCTAssertEqual(failed.openIssueBadge, .unavailable)
        XCTAssertEqual(failed.openPullRequestBadge, .unavailable)
        XCTAssertEqual(failed.openIssueBadge?.text, "—")
        XCTAssertNotEqual(failed.openIssueBadge?.text, zero.openIssueBadge?.text)
        XCTAssertEqual(
            failed.openPullRequestBadge?.accessibilityDescription(singularNoun: "pull request"),
            "Pull request count unavailable"
        )
    }

    func testSingularCountIsAnnouncedForOneOpenItem() {
        let snapshot = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: [], openPullRequestCount: 1, openIssueCount: 1, unavailableReason: nil
            )
        )
        XCTAssertEqual(snapshot.openIssueBadge?.accessibilityDescription(singularNoun: "issue"), "1 open issue")
        XCTAssertEqual(
            snapshot.openPullRequestBadge?.accessibilityDescription(singularNoun: "pull request"),
            "1 open pull request"
        )
    }

    func testLargeTotalsIgnoreTheLimitedPullRequestDetailList() {
        let details = (1 ... 20).map(Self.pullRequest(number:))
        let snapshot = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: details, openPullRequestCount: 34, openIssueCount: 128, unavailableReason: nil
            )
        )

        XCTAssertEqual(snapshot.pullRequests.count, 20)
        XCTAssertEqual(snapshot.openPullRequestBadge, .known(34))
        XCTAssertEqual(snapshot.openPullRequestBadge?.text, "34")
        XCTAssertEqual(snapshot.openIssueBadge, .known(128))
        XCTAssertEqual(snapshot.openIssueBadge?.text, "128")
    }

    func testFourDigitTotalsStayCompact() {
        let badge = GitHubOpenCountBadge.known(1284)
        XCTAssertEqual(badge.text, 1284.formatted(.number.notation(.compactName)))
        XCTAssertNotEqual(badge.text, "1284")
        XCTAssertEqual(badge.accessibilityDescription(singularNoun: "issue"), "1284 open issues")
    }

    func testFailedRefreshShowsLastTotalsAsUnavailable() {
        let snapshot = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: [], openPullRequestCount: 10, openIssueCount: 5, unavailableReason: nil
            ),
            lastErrorDescription: "git status failed"
        )

        XCTAssertEqual(snapshot.openIssueBadge, .unavailable)
        XCTAssertEqual(snapshot.openPullRequestBadge, .unavailable)
    }

    func testOpenTotalsDoNotChangeGitHealthClassification() {
        let known = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: [], openPullRequestCount: 34, openIssueCount: 128, unavailableReason: nil
            )
        )
        let unread = makeSnapshot(gitHubStatus: .empty)

        XCTAssertEqual(known.classification, .clean)
        XCTAssertEqual(known.classification, unread.classification)
        XCTAssertEqual(known.attentionPriority, unread.attentionPriority)
    }

    func testUnavailableCountsFallBackToNeitherZeroNorTheDetailListSize() {
        let snapshot = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: (1 ... 5).map(Self.pullRequest(number:)),
                openPullRequestCount: nil,
                openIssueCount: nil,
                unavailableReason: .gitHubCLIMissing
            )
        )

        XCTAssertEqual(snapshot.openPullRequestBadge, .unavailable)
        XCTAssertEqual(snapshot.openIssueBadge, .unavailable)
        XCTAssertEqual(snapshot.openPullRequestBadge?.text, "—")
    }

    func testPartialFailureKeepsTheCountsThatWereRead() {
        let countsOnly = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: [], openPullRequestCount: 21, openIssueCount: 4, unavailableReason: nil
            )
        )
        XCTAssertEqual(countsOnly.openPullRequestBadge, .known(21))
        XCTAssertEqual(countsOnly.openIssueBadge, .known(4))
    }

    func testNonGitHubRemoteShowsNoBadgesAndKeepsLocalHealth() {
        let snapshot = makeSnapshot(
            gitHubStatus: GitHubProjectStatus(
                pullRequests: [], openPullRequestCount: nil, openIssueCount: nil,
                unavailableReason: .notGitHubRemote
            )
        )

        XCTAssertNil(snapshot.openIssueBadge)
        XCTAssertNil(snapshot.openPullRequestBadge)
        XCTAssertEqual(snapshot.classification, .clean)
    }

    @MainActor
    func testBadgesFollowTheExistingMonitorRefreshCycle() async throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let projects = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        let path = RecentProjectsStore.normalize("/tmp/open-count-badges")
        projects.add(path)
        let monitor = ProjectMonitorStore(
            projectStore: projects,
            agentDetector: AgentActivityDetector(
                processQuerier: MockAgentProcessQuerier(),
                sessionQuerier: MockAgentSessionQuerier()
            )
        )

        monitor.refreshOperation = { project, _ in
            Self.makeSnapshot(
                project: project,
                gitHubStatus: GitHubProjectStatus(
                    pullRequests: [], openPullRequestCount: 3, openIssueCount: 0, unavailableReason: nil
                )
            )
        }
        monitor.refresh(path: path)
        await waitForObservedCondition { monitor.snapshots[path] != nil }
        XCTAssertNil(monitor.snapshots[path]?.openIssueBadge)
        XCTAssertEqual(monitor.snapshots[path]?.openPullRequestBadge, .known(3))

        monitor.refreshOperation = { project, _ in
            Self.makeSnapshot(
                project: project,
                gitHubStatus: GitHubProjectStatus(
                    pullRequests: [], openPullRequestCount: nil, openIssueCount: nil,
                    unavailableReason: .commandFailed
                )
            )
        }
        monitor.refresh(path: path)
        await waitForObservedCondition {
            monitor.snapshots[path]?.gitHubStatus.unavailableReason == .commandFailed
        }
        XCTAssertEqual(monitor.snapshots[path]?.openIssueBadge, .unavailable)
        XCTAssertEqual(monitor.snapshots[path]?.openPullRequestBadge, .unavailable)
    }

    private func makeSnapshot(
        gitHubStatus: GitHubProjectStatus,
        lastErrorDescription: String? = nil
    ) -> ProjectStatusSnapshot {
        Self.makeSnapshot(
            project: ProjectReference(path: "/tmp/open-counts", name: "OpenCounts"),
            gitHubStatus: gitHubStatus,
            lastErrorDescription: lastErrorDescription
        )
    }

    private static func makeSnapshot(
        project: ProjectReference,
        gitHubStatus: GitHubProjectStatus,
        lastErrorDescription: String? = nil
    ) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: project,
            branchName: "main",
            isDetachedHead: false,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: 0,
            behindCount: 0,
            hasUpstream: true,
            lastRefreshedAt: Date(),
            lastErrorDescription: lastErrorDescription,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: 0,
            unmergedBranchCount: 0,
            stashCount: 0,
            lastActivityAt: nil,
            gitHubStatus: gitHubStatus
        )
    }

    private static func pullRequest(number: Int) -> GitHubPullRequestSummary {
        GitHubPullRequestSummary(
            number: number,
            title: "Open pull request \(number)",
            headBranch: "feature/\(number)",
            isDraft: false,
            reviewState: .reviewRequired,
            checksState: .pending,
            url: "https://github.com/example/project/pull/\(number)"
        )
    }
}
