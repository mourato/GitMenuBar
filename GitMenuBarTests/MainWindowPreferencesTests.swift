@testable import GitMenuBar
import SwiftUI
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

    func testShowDockIconDefaultsToEnabledWhenPreferenceIsMissing() {
        let isEnabled = MainWindowPreferences.isShowDockIconEnabled(userDefaults: userDefaults)

        XCTAssertTrue(isEnabled)
    }

    func testShowDockIconPreferenceRoundTrip() {
        MainWindowPreferences.setShowDockIconEnabled(false, userDefaults: userDefaults)
        XCTAssertFalse(MainWindowPreferences.isShowDockIconEnabled(userDefaults: userDefaults))

        MainWindowPreferences.setShowDockIconEnabled(true, userDefaults: userDefaults)
        XCTAssertTrue(MainWindowPreferences.isShowDockIconEnabled(userDefaults: userDefaults))
    }

    func testShowMenuBarIconDefaultsToEnabledWhenPreferenceIsMissing() {
        let isEnabled = MainWindowPreferences.isShowMenuBarIconEnabled(userDefaults: userDefaults)

        XCTAssertTrue(isEnabled)
    }

    func testShowMenuBarIconPreferenceRoundTrip() {
        MainWindowPreferences.setShowMenuBarIconEnabled(false, userDefaults: userDefaults)
        XCTAssertFalse(MainWindowPreferences.isShowMenuBarIconEnabled(userDefaults: userDefaults))

        MainWindowPreferences.setShowMenuBarIconEnabled(true, userDefaults: userDefaults)
        XCTAssertTrue(MainWindowPreferences.isShowMenuBarIconEnabled(userDefaults: userDefaults))
    }
}

@MainActor
final class WorkbenchWindowChromeTests: XCTestCase {
    func testHostedContentControllerRespondsToToggleSidebar() {
        let controller = WorkbenchWindowChrome.makeHostedContentController(rootView: EmptyView())
        XCTAssertTrue(controller.responds(to: #selector(NSSplitViewController.toggleSidebar(_:))))
    }

    func testToggleSidebarTogglesPreference() {
        let controller = WorkbenchWindowChrome.makeHostedContentController(rootView: EmptyView())
        let key = AppPreferences.Keys.isProjectsSidebarCollapsed
        let initial = UserDefaults.standard.bool(forKey: key)
        defer { UserDefaults.standard.set(initial, forKey: key) }

        UserDefaults.standard.set(false, forKey: key)
        controller.perform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        controller.perform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }
}
