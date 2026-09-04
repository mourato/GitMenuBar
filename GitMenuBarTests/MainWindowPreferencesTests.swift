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

    func testToggleShortcutMonitorSelectionDefaultsToDisabledWhenPreferenceIsMissing() {
        let isEnabled = MainWindowPreferences.isToggleShortcutUsingMouseMonitorEnabled(
            userDefaults: userDefaults
        )

        XCTAssertFalse(isEnabled)
    }

    func testToggleShortcutMonitorSelectionPreferenceRoundTrip() {
        MainWindowPreferences.setToggleShortcutUsingMouseMonitorEnabled(true, userDefaults: userDefaults)
        XCTAssertTrue(
            MainWindowPreferences.isToggleShortcutUsingMouseMonitorEnabled(userDefaults: userDefaults)
        )

        MainWindowPreferences.setToggleShortcutUsingMouseMonitorEnabled(false, userDefaults: userDefaults)
        XCTAssertFalse(
            MainWindowPreferences.isToggleShortcutUsingMouseMonitorEnabled(userDefaults: userDefaults)
        )
    }

    func testInspectorColumnWidthDefaultsToMetricWhenPreferenceIsMissingOrInvalid() {
        XCTAssertEqual(
            MainWindowPreferences.inspectorColumnWidth(userDefaults: userDefaults),
            Double(WorkbenchMetrics.inspectorDefaultWidth)
        )

        userDefaults.set(0.0, forKey: AppPreferences.Keys.inspectorColumnWidth)
        XCTAssertEqual(
            MainWindowPreferences.inspectorColumnWidth(userDefaults: userDefaults),
            Double(WorkbenchMetrics.inspectorDefaultWidth)
        )
    }

    func testInspectorColumnWidthPreferenceRoundTrip() {
        MainWindowPreferences.setInspectorColumnWidth(864.0, userDefaults: userDefaults)

        XCTAssertEqual(
            MainWindowPreferences.inspectorColumnWidth(userDefaults: userDefaults),
            864.0
        )
    }
}
