@testable import GitMenuBar
import XCTest

final class MainWindowPreferencesTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MainWindowPreferencesTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let userDefaults, let suiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAutoHideDefaultsToDisabledWhenPreferenceIsMissing() {
        let isEnabled = MainWindowPreferences.isAutoHideOnBlurEnabled(userDefaults: userDefaults)

        XCTAssertFalse(isEnabled)
    }

    func testAutoHidePreferenceRoundTrip() {
        MainWindowPreferences.setAutoHideOnBlurEnabled(true, userDefaults: userDefaults)
        XCTAssertTrue(MainWindowPreferences.isAutoHideOnBlurEnabled(userDefaults: userDefaults))

        MainWindowPreferences.setAutoHideOnBlurEnabled(false, userDefaults: userDefaults)
        XCTAssertFalse(MainWindowPreferences.isAutoHideOnBlurEnabled(userDefaults: userDefaults))
    }
}
