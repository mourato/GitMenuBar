@testable import GitMenuBar
import XCTest

@MainActor
final class MainMenuRouteTransitionTests: XCTestCase {
    func testPreferredColorSchemeResolvesAllModes() {
        XCTAssertNil(AppPreferences.AppearanceMode.systemDefault.preferredColorScheme)
        XCTAssertEqual(AppPreferences.AppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(AppPreferences.AppearanceMode.dark.preferredColorScheme, .dark)
    }
}
