@testable import GitMenuBar
import XCTest

@MainActor
final class MainMenuRouteTransitionTests: XCTestCase {
    func testPreferredColorSchemeResolvesAllModes() {
        XCTAssertNil(AppPreferences.AppearanceMode.systemDefault.preferredColorScheme)
        XCTAssertEqual(AppPreferences.AppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(AppPreferences.AppearanceMode.dark.preferredColorScheme, .dark)
    }

    func testTransitionCoversEveryRouteWithAndWithoutReducedMotion() {
        let routes: [MainMenuRoute] = [.main, .createRepo(path: "/tmp/demo"), .projectCleanup]

        for route in routes {
            for reduceMotion in [false, true] {
                // Smoke: every route/motion combination must resolve without trapping.
                _ = MainMenuRouteTransition.transition(for: route, reduceMotion: reduceMotion)
            }
        }
    }
}
