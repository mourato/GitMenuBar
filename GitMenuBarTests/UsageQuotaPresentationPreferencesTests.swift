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
}
