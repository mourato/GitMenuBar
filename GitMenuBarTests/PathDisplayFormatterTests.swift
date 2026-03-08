@testable import GitMenuBar
import XCTest

final class PathDisplayFormatterTests: XCTestCase {
    func testProjectNameUsesLastPathComponent() {
        XCTAssertEqual(
            PathDisplayFormatter.projectName(from: "/Users/test/Projects/gitmenubar"),
            "gitmenubar"
        )
    }

    func testRecentProjectLabelSwitchesBetweenModes() {
        let path = "/Users/test/Projects/gitmenubar"

        XCTAssertEqual(
            PathDisplayFormatter.recentProjectLabel(for: path, showFullPath: false),
            "gitmenubar"
        )
        XCTAssertTrue(
            PathDisplayFormatter.recentProjectLabel(for: path, showFullPath: true).contains("gitmenubar")
        )
    }
}
