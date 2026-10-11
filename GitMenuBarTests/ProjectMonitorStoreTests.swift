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
