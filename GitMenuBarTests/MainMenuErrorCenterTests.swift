@testable import GitMenuBar
import XCTest

@MainActor
final class MainMenuErrorCenterTests: XCTestCase {
    func testClearRemovesOnlyMatchingDomain() {
        let center = MainMenuErrorCenter()
        center.sync = "Sync Failed"
        center.merge = "Merge Failed"

        center.clear(.sync)

        XCTAssertNil(center.sync)
        XCTAssertEqual(center.merge, "Merge Failed")
    }

    func testClearCoversEveryErrorDomain() {
        let center = MainMenuErrorCenter()
        center.deleteRepository = "a"
        center.toggleVisibility = "b"
        center.discard = "c"
        center.sync = "d"
        center.branchSwitch = "e"
        center.merge = "f"
        center.deleteBranch = "g"
        center.renameBranch = "h"
        center.restart = "i"
        center.push = "j"

        let sources: [MainMenuInlineBannerSource] = [
            .deleteRepository, .toggleVisibility, .discard, .sync, .branchSwitch,
            .merge, .deleteBranch, .renameBranch, .restart, .push
        ]
        for source in sources {
            center.clear(source)
        }

        XCTAssertNil(center.deleteRepository)
        XCTAssertNil(center.toggleVisibility)
        XCTAssertNil(center.discard)
        XCTAssertNil(center.sync)
        XCTAssertNil(center.branchSwitch)
        XCTAssertNil(center.merge)
        XCTAssertNil(center.deleteBranch)
        XCTAssertNil(center.renameBranch)
        XCTAssertNil(center.restart)
        XCTAssertNil(center.push)
    }

    func testClearIgnoresCoordinatorSources() {
        let center = MainMenuErrorCenter()
        center.sync = "Sync Failed"

        center.clear(.coordinatorAlert)
        center.clear(.coordinatorSuccess)

        XCTAssertEqual(center.sync, "Sync Failed")
    }
}
