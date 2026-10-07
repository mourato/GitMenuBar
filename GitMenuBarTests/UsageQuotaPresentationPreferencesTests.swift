@testable import GitMenuBar
import XCTest

@MainActor
final class UsageQuotaPresentationPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "UsageQuotaPresentationPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPersistsDisplayAndProviderOrder() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.meterStyle = .bars
        preferences.valueStyle = .used
        preferences.moveProvider(.cursor, by: -2)

        let restored = UsageQuotaPresentationPreferences(defaults: defaults)

        XCTAssertEqual(restored.meterStyle, .bars)
        XCTAssertEqual(restored.valueStyle, .used)
        XCTAssertEqual(restored.orderedProviderIDs.first, .cursor)
    }

    func testPersistsMenuBarVisibility() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.menuBarVisibility = .menuOnly

        let restored = UsageQuotaPresentationPreferences(defaults: defaults)

        XCTAssertEqual(restored.menuBarVisibility, .menuOnly)
    }

    func testPersistsAtMostTwoSelectedMetrics() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.setSelectedMetrics([.credits, .weekly, .session], for: .codex)

        let restored = UsageQuotaPresentationPreferences(defaults: defaults)

        XCTAssertEqual(restored.selectedMetrics(for: .codex), [.credits, .weekly])
    }

    func testTogglingThirdMetricReplacesSecondMetric() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.setSelectedMetrics([.session, .weekly], for: .codex)

        preferences.toggleMetric(.credits, for: .codex)

        XCTAssertEqual(preferences.selectedMetrics(for: .codex), [.session, .credits])
    }

    func testBarMarkerDefaults() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)

        XCTAssertEqual(preferences.sessionWarningThresholds, [50, 80])
        XCTAssertEqual(preferences.weeklyWarningThresholds, [50, 80])
        XCTAssertEqual(preferences.workdaysPerWeek, 5)
        XCTAssertEqual(preferences.workdayTickAppearance, .subtle)
        XCTAssertTrue(preferences.showsPace)
    }

    func testPersistsBarMarkerPreferences() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.sessionWarningThresholds = [30, 90]
        preferences.weeklyWarningThresholds = [60]
        preferences.workdaysPerWeek = 3
        preferences.workdayTickAppearance = .hidden
        preferences.showsPace = false

        let restored = UsageQuotaPresentationPreferences(defaults: defaults)

        XCTAssertEqual(restored.sessionWarningThresholds, [30, 90])
        XCTAssertEqual(restored.weeklyWarningThresholds, [60])
        XCTAssertEqual(restored.workdaysPerWeek, 3)
        XCTAssertEqual(restored.workdayTickAppearance, .hidden)
        XCTAssertFalse(restored.showsPace)
    }

    func testWarningThresholdsAreValidated() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.setSessionWarningThresholds([90, 0, 200, 90])

        XCTAssertEqual(preferences.sessionWarningThresholds, [1, 90, 99])

        preferences.setWeeklyWarningThresholds([])

        XCTAssertEqual(preferences.weeklyWarningThresholds, [])
        XCTAssertEqual(UsageQuotaPresentationPreferences(defaults: defaults).weeklyWarningThresholds, [])
    }

    func testWarningThresholdsDefaultWhenUnset() {
        XCTAssertEqual(UsageQuotaPresentationPreferences(defaults: defaults).sessionWarningThresholds, [50, 80])
    }

    func testWorkdaysPerWeekAreClamped() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.setWorkdaysPerWeek(0)

        XCTAssertEqual(preferences.workdaysPerWeek, 1)

        preferences.setWorkdaysPerWeek(9)

        XCTAssertEqual(preferences.workdaysPerWeek, 7)
    }

    func testThresholdTextCommit() {
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.setSessionWarningThresholds(from: "90, 30")

        XCTAssertEqual(preferences.sessionWarningThresholds, [30, 90])

        preferences.setWeeklyWarningThresholds(from: "nothing usable")

        XCTAssertEqual(preferences.weeklyWarningThresholds, [50, 80])

        preferences.setWeeklyWarningThresholds(from: " ")

        XCTAssertEqual(preferences.weeklyWarningThresholds, [])
    }
}
