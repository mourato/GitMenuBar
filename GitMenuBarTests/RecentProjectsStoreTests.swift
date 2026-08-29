@testable import GitMenuBar
import XCTest

final class RecentProjectsStoreTests: XCTestCase {
    func testAddsProjectToTopAndDeduplicates() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents", maxCount: 5)

        store.add("/tmp/a")
        store.add("/tmp/b")
        store.add("/tmp/a")

        XCTAssertEqual(store.recentPaths(), ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(
            store.recentProjects(),
            [
                ProjectReference(path: "/tmp/a", name: "a"),
                ProjectReference(path: "/tmp/b", name: "b")
            ]
        )
    }

    func testRespectsMaxCount() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents", maxCount: 3)

        store.add("/tmp/a")
        store.add("/tmp/b")
        store.add("/tmp/c")
        store.add("/tmp/d")

        XCTAssertEqual(store.recentPaths(), ["/tmp/d", "/tmp/c", "/tmp/b"])
    }

    func testMigratesLegacyPathArrayToNamedProjects() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let legacyPaths = ["/tmp/client-a", "/tmp/client-b"]
        let data = try JSONEncoder().encode(legacyPaths)
        defaults.set(data, forKey: "recents")

        let store = RecentProjectsStore(defaults: defaults, key: "recents", maxCount: 5)

        XCTAssertEqual(
            store.recentProjects(),
            [
                ProjectReference(path: "/tmp/client-a", name: "client-a"),
                ProjectReference(path: "/tmp/client-b", name: "client-b")
            ]
        )
        XCTAssertEqual(store.recentPaths(), legacyPaths)
    }

    func testReaddingExistingProjectPreservesCustomName() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents", maxCount: 5)

        store.upsert(path: "/tmp/a", name: "Client A")
        store.add("/tmp/b")
        store.add("/tmp/a")

        XCTAssertEqual(store.recentProjects().first, ProjectReference(path: "/tmp/a", name: "Client A"))
    }

    func testUpsertExistingProjectUpdatesCustomName() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents", maxCount: 5)

        store.upsert(path: "/tmp/a", name: "Client A")
        store.upsert(path: "/tmp/a", name: "Renamed Client")

        XCTAssertEqual(store.recentProjects(), [ProjectReference(path: "/tmp/a", name: "Renamed Client")])
    }

    func testRenameTrimsWhitespaceAndResetsEmptyNameToDefault() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents", maxCount: 5)

        store.rename(path: "/tmp/client-a", name: "  Client A  ")
        XCTAssertEqual(store.displayName(for: "/tmp/client-a"), "Client A")

        store.rename(path: "/tmp/client-a", name: "   ")
        XCTAssertEqual(store.displayName(for: "/tmp/client-a"), "client-a")
    }

    func testRemoveDeletesOnlyMatchingProject() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents")
        store.add("/tmp/a"); store.add("/tmp/b"); store.add("/tmp/c")
        store.remove(path: "/tmp/b")
        XCTAssertEqual(store.recentPaths(), ["/tmp/c", "/tmp/a"])
    }

    func testRemoveNormalizesPathBeforeMatching() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents")
        store.add("/tmp/a")
        store.remove(path: "/tmp/./a")
        XCTAssertTrue(store.recentProjects().isEmpty)
    }

    func testRemoveMissingProjectIsNoOp() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents")
        store.add("/tmp/a")
        store.remove(path: "/tmp/missing")
        XCTAssertEqual(store.recentPaths(), ["/tmp/a"])
    }

    func testRemovePreservesCustomNamesOnRemainingProjects() throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents")
        store.upsert(path: "/tmp/a", name: "Alpha")
        store.upsert(path: "/tmp/b", name: "Beta")
        store.remove(path: "/tmp/a")
        XCTAssertEqual(store.recentProjects(), [ProjectReference(path: "/tmp/b", name: "Beta")])
    }
}
