@testable import GitMenuBar
import XCTest

final class MainWindowShortcutQueueTests: XCTestCase {
    func testDequeueReturnsNothingWhenWindowIsHidden() {
        var queue = MainWindowShortcutQueue()

        queue.enqueue(.commit)
        let actions = queue.dequeueAllIfReady(isWindowVisible: false, isMainRoute: true)

        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(queue.pendingActions, [.commit])
    }

    func testDequeueReturnsNothingWhenMainRouteIsNotVisible() {
        var queue = MainWindowShortcutQueue()

        queue.enqueue(.sync)
        let actions = queue.dequeueAllIfReady(isWindowVisible: true, isMainRoute: false)

        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(queue.pendingActions, [.sync])
    }

    func testDequeueFlushesAllActionsInFIFOOrder() {
        var queue = MainWindowShortcutQueue()

        queue.enqueue(.commit)
        queue.enqueue(.sync)

        let actions = queue.dequeueAllIfReady(isWindowVisible: true, isMainRoute: true)

        XCTAssertEqual(actions, [.commit, .sync])
        XCTAssertTrue(queue.pendingActions.isEmpty)
    }
}
