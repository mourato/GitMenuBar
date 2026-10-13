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

    private static func snapshot(path: String) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: path), branchName: "main", isDetachedHead: false,
            stagedCount: 0, unstagedCount: 0, untrackedCount: 0, lineDiff: .zero,
            aheadCount: 0, behindCount: 0, hasUpstream: true, lastRefreshedAt: Date(),
            lastErrorDescription: nil, branchesWithoutUpstreamCount: 0, unpushedBranchCount: 0,
            unmergedBranchCount: 0, stashCount: 0, lastActivityAt: nil, pullRequests: []
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
