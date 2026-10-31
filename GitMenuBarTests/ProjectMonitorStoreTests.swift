@testable import GitMenuBar
import XCTest

final class ProjectMonitorStoreTests: XCTestCase {
    @MainActor
    func testGitRefreshPreservesAgentsAndAgentRefreshPreservesSnapshots() async throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let projects = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        let path = RecentProjectsStore.normalize("/tmp/agent-project")
        projects.add(path)
        let activity = AgentProjectActivity(harness: .claudeCode, status: .running)
        let detector = AgentActivityDetector(
            processQuerier: MockAgentProcessQuerier(),
            sessionQuerier: MockAgentSessionQuerier(sessions: [path: [activity]])
        )
        let monitor = ProjectMonitorStore(projectStore: projects, agentDetector: detector)
        monitor.setAgentActivityVisible(true)
        defer { monitor.setAgentActivityVisible(false) }
        await monitor.refreshAgentActivity()
        XCTAssertEqual(monitor.agentActivities[path], [activity])
        XCTAssertTrue(monitor.snapshots.isEmpty)

        monitor.refreshOperation = { project, _ in Self.snapshot(path: project.path) }
        monitor.refresh(path: path)
        await waitForObservedCondition { monitor.snapshots[path] != nil }
        XCTAssertEqual(monitor.snapshots[path]?.branchName, "main")
        XCTAssertEqual(monitor.agentActivities[path], [activity])
        let snapshots = monitor.snapshots
        await monitor.refreshAgentActivity()
        XCTAssertEqual(monitor.snapshots, snapshots)
    }

    @MainActor
    func testStaleAgentResultIsDiscardedAndOverlapsAreCoalesced() async throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let projects = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        let path = RecentProjectsStore.normalize("/tmp/stale-agent-project")
        projects.add(path)
        let started = expectation(description: "agent query started")
        let finished = expectation(description: "agent query finished")
        let sessions = SuspendedAgentSessionQuerier(path: path, started: started, finished: finished)
        let monitor = ProjectMonitorStore(
            projectStore: projects,
            agentDetector: AgentActivityDetector(processQuerier: MockAgentProcessQuerier(), sessionQuerier: sessions)
        )
        await monitor.refreshAgentActivity()
        let initialCount = await sessions.queryCount
        XCTAssertEqual(initialCount, 0)
        monitor.setAgentActivityVisible(true)
        await fulfillment(of: [started], timeout: 5)
        await monitor.refreshAgentActivity()
        let overlappingCount = await sessions.queryCount
        XCTAssertEqual(overlappingCount, 1)
        monitor.setAgentActivityVisible(false)
        await sessions.release()
        await fulfillment(of: [finished], timeout: 5)
        await Task.yield()
        XCTAssertTrue(monitor.agentActivities.isEmpty)
        await monitor.refreshAgentActivity()
        let disabledCount = await sessions.queryCount
        XCTAssertEqual(disabledCount, 1)
    }

    @MainActor
    func testLocalMonitorRefreshPreservesLastKnownBranchHealthAndPullRequests() async throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let projects = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        let root = try createTemporaryGitRepository(testName: #function)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = RecentProjectsStore.normalize(root.path)
        projects.add(path)

        // Real repository branch health the local refresh must not re-read.
        try "stashed\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["stash", "push", "-qm", "seeded work"], in: root)

        let pullRequest = GitHubPullRequestSummary(
            number: 7,
            title: "Open pull request",
            headBranch: "feature/local",
            isDraft: false,
            reviewState: .reviewRequired,
            checksState: .pending,
            url: "https://github.com/example/project/pull/7"
        )
        let monitor = ProjectMonitorStore(
            projectStore: projects,
            agentDetector: AgentActivityDetector(
                processQuerier: MockAgentProcessQuerier(),
                sessionQuerier: MockAgentSessionQuerier()
            )
        )
        // Seed the previous snapshot (branch health + pull requests) through
        // the DEBUG hook, then exercise the real local refresh path.
        monitor.refreshOperation = { project, _ in
            ProjectStatusSnapshot(
                project: project, branchName: "main", isDetachedHead: false,
                stagedCount: 0, unstagedCount: 0, untrackedCount: 0, lineDiff: .zero,
                aheadCount: 0, behindCount: 0, hasUpstream: false, lastRefreshedAt: Date(),
                lastErrorDescription: nil, branchesWithoutUpstreamCount: 1, unpushedBranchCount: 0,
                unmergedBranchCount: 0, stashCount: 1, lastActivityAt: Date(timeIntervalSince1970: 1000),
                gitHubStatus: GitHubProjectStatus(
                    pullRequests: [pullRequest], openPullRequestCount: 1, openIssueCount: 2, unavailableReason: nil
                )
            )
        }
        monitor.refresh(path: path)
        await waitForObservedCondition { monitor.snapshots[path] != nil }
        monitor.refreshOperation = nil
        let seeded = monitor.snapshots[path]
        XCTAssertEqual(seeded?.stashCount, 1)
        XCTAssertEqual(seeded?.pullRequests, [pullRequest])
        XCTAssertEqual(seeded?.openPullRequestCount, 1)
        XCTAssertEqual(seeded?.openIssueCount, 2)

        // Mutate the working tree and remove the stash, so both a fresh
        // working-tree value and a fresh branch-health read would differ.
        try "changed\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["stash", "clear"], in: root)

        monitor.refresh(path: path, includeRemoteData: false)
        await waitForObservedCondition { monitor.snapshots[path]?.unstagedCount == 1 }

        // Working-tree values are live, but branch health and pull requests
        // match the previous snapshot rather than the repository.
        XCTAssertEqual(monitor.snapshots[path]?.branchesWithoutUpstreamCount, seeded?.branchesWithoutUpstreamCount)
        XCTAssertEqual(monitor.snapshots[path]?.unpushedBranchCount, seeded?.unpushedBranchCount)
        XCTAssertEqual(monitor.snapshots[path]?.unmergedBranchCount, seeded?.unmergedBranchCount)
        XCTAssertEqual(monitor.snapshots[path]?.stashCount, seeded?.stashCount)
        XCTAssertEqual(monitor.snapshots[path]?.lastActivityAt, seeded?.lastActivityAt)
        XCTAssertEqual(monitor.snapshots[path]?.pullRequests, [pullRequest])
        XCTAssertEqual(monitor.snapshots[path]?.openPullRequestCount, seeded?.openPullRequestCount)
        XCTAssertEqual(monitor.snapshots[path]?.openIssueCount, seeded?.openIssueCount)
        XCTAssertNil(monitor.snapshots[path]?.lastErrorDescription)

        // A full refresh still re-reads branch health and pull requests.
        monitor.refresh(path: path)
        await waitForObservedCondition { monitor.snapshots[path]?.stashCount == 0 }
        XCTAssertEqual(monitor.snapshots[path]?.pullRequests, [])
        XCTAssertNil(monitor.snapshots[path]?.openPullRequestCount)
        XCTAssertNil(monitor.snapshots[path]?.openIssueCount)
        XCTAssertEqual(monitor.snapshots[path]?.unstagedCount, 1)
    }

    private static func snapshot(path: String) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: path), branchName: "main", isDetachedHead: false,
            stagedCount: 0, unstagedCount: 0, untrackedCount: 0, lineDiff: .zero,
            aheadCount: 0, behindCount: 0, hasUpstream: true, lastRefreshedAt: Date(),
            lastErrorDescription: nil, branchesWithoutUpstreamCount: 0, unpushedBranchCount: 0,
            unmergedBranchCount: 0, stashCount: 0, lastActivityAt: nil, gitHubStatus: .empty
        )
    }
}

private actor SuspendedAgentSessionQuerier: AgentSessionQuerying {
    let path: String
    let started: XCTestExpectation
    let finished: XCTestExpectation
    private(set) var queryCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(path: String, started: XCTestExpectation, finished: XCTestExpectation) {
        self.path = path
        self.started = started
        self.finished = finished
    }

    func recentActivities(for _: [String], now _: Date) async -> [String: [AgentProjectActivity]] {
        queryCount += 1
        if !released {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
        finished.fulfill()
        return [path: [AgentProjectActivity(harness: .codex, status: .running)]]
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
