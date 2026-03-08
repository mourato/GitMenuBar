@testable import GitMenuBar
import XCTest

final class RecentProjectsStoreTests: XCTestCase {
    func testAddsProjectToTopAndDeduplicates() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents", maxCount: 5)

        store.add("/tmp/a")
        store.add("/tmp/b")
        store.add("/tmp/a")

        XCTAssertEqual(store.recentPaths(), ["/tmp/a", "/tmp/b"])
    }

    func testRespectsMaxCount() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let store = RecentProjectsStore(defaults: defaults, key: "recents", maxCount: 3)

        store.add("/tmp/a")
        store.add("/tmp/b")
        store.add("/tmp/c")
        store.add("/tmp/d")

        XCTAssertEqual(store.recentPaths(), ["/tmp/d", "/tmp/c", "/tmp/b"])
    }
}
