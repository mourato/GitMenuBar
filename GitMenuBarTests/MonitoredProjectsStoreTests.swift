import Combine
@testable import GitMenuBar
import XCTest

final class MonitoredProjectsStoreTests: XCTestCase {
    func testAddsDeduplicatesAndRespectsLimit() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let store = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded", maxCount: 2)

        store.add("/tmp/a")
        store.add("/tmp/b")
        store.add("/tmp/a")
        store.add("/tmp/c")

        XCTAssertEqual(store.monitoredProjects().map(\.path), ["/tmp/c", "/tmp/a"])
    }

    func testSeedsCurrentAndRecentsOnlyOnce() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let store = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        let recents = [ProjectReference(path: "/tmp/recent")]

        store.seedIfNeeded(currentPath: "/tmp/current", recentProjects: recents)
        store.seedIfNeeded(currentPath: "/tmp/other", recentProjects: [])

        XCTAssertEqual(store.monitoredProjects().map(\.path), ["/tmp/current", "/tmp/recent"])
    }

    func testRemoveNormalizesPath() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let store = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        store.add("/tmp/project")

        store.remove(path: "/tmp/./project")

        XCTAssertTrue(store.monitoredProjects().isEmpty)
    }

    func testRenamePreservesProjectOrder() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let store = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        store.add("/tmp/first")
        store.add("/tmp/second")
        store.add("/tmp/third")

        store.rename(path: "/tmp/second", name: "Second")

        XCTAssertEqual(store.monitoredProjects().map(\.path), ["/tmp/third", "/tmp/second", "/tmp/first"])
        XCTAssertEqual(store.monitoredProjects()[1].name, "Second")
    }

    func testCleanSnapshotClassification() {
        let snapshot = ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/project"), branchName: "main", isDetachedHead: false,
            stagedCount: 0, unstagedCount: 0, untrackedCount: 0, lineDiff: .zero, aheadCount: 0, behindCount: 0,
            hasUpstream: true, lastRefreshedAt: Date(), lastErrorDescription: nil
        )

        XCTAssertEqual(snapshot.classification, .clean)
    }

    func testDirtyAndDivergedSnapshotNeedsAttention() {
        let snapshot = ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/project"), branchName: "main", isDetachedHead: false,
            stagedCount: 1, unstagedCount: 0, untrackedCount: 0,
            lineDiff: LineDiffStats(added: 3, removed: 1), aheadCount: 2, behindCount: 1,
            hasUpstream: true, lastRefreshedAt: Date(), lastErrorDescription: nil
        )

        XCTAssertEqual(snapshot.classification, .needsAttention)
        XCTAssertTrue(snapshot.reasons.contains(.dirty))
        XCTAssertTrue(snapshot.reasons.contains(.diverged))
    }

    @MainActor
    func testSeedIgnoresNonGitRecentProjects() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMenuBarMonitorSeed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let validPath = root.appendingPathComponent("valid").path
        let invalidPath = root.appendingPathComponent("invalid").path
        try FileManager.default.createDirectory(atPath: validPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: invalidPath, withIntermediateDirectories: true)
        _ = try runGit(["init", "-q"], in: URL(fileURLWithPath: validPath))

        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let store = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        let monitor = ProjectMonitorStore(projectStore: store)

        await monitor.seed(
            currentPath: invalidPath,
            recentProjects: [ProjectReference(path: validPath), ProjectReference(path: invalidPath)]
        )

        XCTAssertEqual(store.monitoredProjects().map(\.path), [validPath])
        XCTAssertEqual(monitor.snapshots[validPath]?.project.path, validPath)
    }

    @MainActor
    func testFetchDoesNotReinsertRemovedProject() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let projectStore = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        projectStore.add("/tmp/removed")
        let monitor = ProjectMonitorStore(projectStore: projectStore)
        let started = expectation(description: "fetch started")
        let release = expectation(description: "release fetch")
        let finished = expectation(description: "fetch finished")
        monitor.fetchOperation = { project, _ in
            started.fulfill()
            _ = XCTWaiter.wait(for: [release], timeout: 5)
            finished.fulfill()
            return Self.snapshot(path: project.path, branch: "stale")
        }

        monitor.fetchAll()
        await fulfillment(of: [started])
        monitor.remove(path: "/tmp/removed")
        release.fulfill()
        await fulfillment(of: [finished])
        await Task.yield()

        XCTAssertTrue(monitor.monitoredProjects.isEmpty)
        XCTAssertNil(monitor.snapshots[RecentProjectsStore.normalize("/tmp/removed")])
    }

    @MainActor
    func testNewerLocalRefreshWinsOverFetch() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let projectStore = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        projectStore.add("/tmp/project")
        let monitor = ProjectMonitorStore(projectStore: projectStore)
        let started = expectation(description: "fetch started")
        let release = expectation(description: "release fetch")
        let finished = expectation(description: "fetch finished")
        let newerSnapshotPublished = expectation(description: "newer snapshot published")
        monitor.fetchOperation = { project, _ in
            started.fulfill()
            _ = XCTWaiter.wait(for: [release], timeout: 5)
            finished.fulfill()
            return Self.snapshot(path: project.path, branch: "stale")
        }
        monitor.refreshOperation = { project, _ in
            Self.snapshot(path: project.path, branch: "newer")
        }
        let observation = monitor.$snapshots.sink { snapshots in
            if snapshots["/tmp/project"]?.branchName == "newer" {
                newerSnapshotPublished.fulfill()
            }
        }
        defer { observation.cancel() }

        monitor.fetchAll()
        await fulfillment(of: [started])
        monitor.refresh(path: "/tmp/project")
        await fulfillment(of: [newerSnapshotPublished])
        XCTAssertEqual(monitor.snapshots["/tmp/project"]?.branchName, "newer")

        release.fulfill()
        await fulfillment(of: [finished])
        XCTAssertEqual(monitor.snapshots["/tmp/project"]?.branchName, "newer")
    }

    @MainActor
    func testFetchSkipsWhileLocalRefreshIsActive() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let projectStore = MonitoredProjectsStore(defaults: defaults, key: "projects", seededKey: "seeded")
        projectStore.add("/tmp/project")
        let monitor = ProjectMonitorStore(projectStore: projectStore)
        let refreshStarted = expectation(description: "refresh started")
        let releaseRefresh = expectation(description: "release refresh")
        let refreshFinished = expectation(description: "refresh finished")
        let fetchStarted = expectation(description: "fetch started")
        monitor.refreshOperation = { project, _ in
            refreshStarted.fulfill()
            _ = XCTWaiter.wait(for: [releaseRefresh], timeout: 5)
            refreshFinished.fulfill()
            return Self.snapshot(path: project.path, branch: "newer")
        }
        monitor.fetchOperation = { project, _ in
            fetchStarted.fulfill()
            return Self.snapshot(path: project.path, branch: "fetch")
        }

        monitor.refresh(path: "/tmp/project")
        await fulfillment(of: [refreshStarted])
        monitor.fetchAll()
        XCTAssertEqual(XCTWaiter.wait(for: [fetchStarted], timeout: 0), .timedOut)
        releaseRefresh.fulfill()
        await fulfillment(of: [refreshFinished])
    }

    private static func snapshot(path: String, branch: String) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: path), branchName: branch, isDetachedHead: false,
            stagedCount: 0, unstagedCount: 0, untrackedCount: 0, lineDiff: .zero,
            aheadCount: 0, behindCount: 0, hasUpstream: true, lastRefreshedAt: Date(),
            lastErrorDescription: nil
        )
    }
}
