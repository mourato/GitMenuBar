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
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while monitor.snapshots[path] == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
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
        let sessions = SuspendedAgentSessionQuerier(path: path)
        let monitor = ProjectMonitorStore(
            projectStore: projects,
            agentDetector: AgentActivityDetector(processQuerier: MockAgentProcessQuerier(), sessionQuerier: sessions)
        )
        await monitor.refreshAgentActivity()
        let initialCount = await sessions.queryCount
        XCTAssertEqual(initialCount, 0)
        monitor.setAgentActivityVisible(true)
        await sessions.waitUntilStarted()
        await monitor.refreshAgentActivity()
        let overlappingCount = await sessions.queryCount
        XCTAssertEqual(overlappingCount, 1)
        monitor.setAgentActivityVisible(false)
        await sessions.release()
        await sessions.waitUntilFinished()
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
    private(set) var queryCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var finished: CheckedContinuation<Void, Never>?
    private var didFinish = false

    init(path: String) {
        self.path = path
    }

    func recentActivities(for _: [String], now _: Date) async -> [String: [AgentProjectActivity]] {
        queryCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
        didFinish = true
        finished?.resume()
        finished = nil
        return [path: [AgentProjectActivity(harness: .codex, status: .running)]]
    }

    func waitUntilStarted() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func waitUntilFinished() async {
        if didFinish {
            return
        }
        await withCheckedContinuation { finished = $0 }
    }
}
