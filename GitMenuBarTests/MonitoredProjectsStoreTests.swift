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

        XCTAssertEqual(store.monitoredProjects().map(\.path), ["/tmp/b", "/tmp/a"])
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

    func testCleanSnapshotClassification() {
        let snapshot = ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/project"), branchName: "main", isDetachedHead: false,
            stagedCount: 0, unstagedCount: 0, untrackedCount: 0, aheadCount: 0, behindCount: 0,
            hasUpstream: true, lastRefreshedAt: Date(), lastErrorDescription: nil
        )

        XCTAssertEqual(snapshot.classification, .clean)
    }

    func testDirtyAndDivergedSnapshotNeedsAttention() {
        let snapshot = ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/project"), branchName: "main", isDetachedHead: false,
            stagedCount: 1, unstagedCount: 0, untrackedCount: 0, aheadCount: 2, behindCount: 1,
            hasUpstream: true, lastRefreshedAt: Date(), lastErrorDescription: nil
        )

        XCTAssertEqual(snapshot.classification, .needsAttention)
        XCTAssertTrue(snapshot.reasons.contains(.dirty))
        XCTAssertTrue(snapshot.reasons.contains(.diverged))
    }
}
