@testable import GitMenuBar
import XCTest

/// Contract for the quota settings status pill: the same snapshot rules that
/// drive the menu-bar strip must drive the per-provider status text.
final class QuotaProviderStatusTests: XCTestCase {
    private func window(remainingPercent: Int = 62) -> UsageWindow {
        UsageWindow(remainingPercent: remainingPercent, resetAt: nil, label: "5h")
    }

    private func resolve(
        isEnabled: Bool,
        snapshot: UsageQuotaSnapshot?,
        isKeyProvider: Bool = false,
        hasStoredKey: Bool = false,
        selectedMetrics: [UsageQuotaPresentationPreferences.Metric] = [.session, .weekly]
    ) -> QuotaProviderStatus {
        QuotaProviderStatus.resolve(
            isEnabled: isEnabled,
            snapshot: snapshot,
            isKeyProvider: isKeyProvider,
            hasStoredKey: hasStoredKey,
            selectedMetrics: selectedMetrics
        )
    }

    func testDisabledProviderIsHidden() {
        XCTAssertEqual(resolve(isEnabled: false, snapshot: nil), .hidden)
    }

    func testEnabledProviderWithoutSnapshotIsChecking() {
        XCTAssertEqual(resolve(isEnabled: true, snapshot: nil), .checking)
    }

    func testNilSnapshotKeyProviderWithoutKeyNeedsKey() {
        XCTAssertEqual(
            resolve(isEnabled: true, snapshot: nil, isKeyProvider: true, hasStoredKey: false),
            .needsKey
        )
    }

    func testNilSnapshotKeyProviderWithKeyIsChecking() {
        XCTAssertEqual(
            resolve(isEnabled: true, snapshot: nil, isKeyProvider: true, hasStoredKey: true),
            .checking
        )
    }

    func testAvailableSnapshotWithSessionWindowIsInStrip() {
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: window(),
            weeklyWindow: nil,
            isAvailable: true
        )
        XCTAssertEqual(resolve(isEnabled: true, snapshot: snapshot), .inStrip)
    }

    func testAvailableSnapshotWithOnlyModelWindowsIsInStrip() {
        let snapshot = UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            sessionWindow: nil,
            weeklyWindow: nil,
            modelWindows: [window()],
            isAvailable: true
        )
        XCTAssertEqual(resolve(isEnabled: true, snapshot: snapshot), .inStrip)
    }

    func testAvailableSnapshotWithoutWindowsIsNoData() {
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: nil,
            weeklyWindow: nil,
            isAvailable: true
        )
        XCTAssertEqual(resolve(isEnabled: true, snapshot: snapshot), .noData)
    }

    func testExhaustedWeeklyWindowIsNoData() {
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: window(),
            weeklyWindow: window(remainingPercent: 0),
            isAvailable: true
        )
        XCTAssertEqual(resolve(isEnabled: true, snapshot: snapshot), .noData)
    }

    func testUncoveredSelectedMetricIsNoData() {
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: window(),
            weeklyWindow: nil,
            isAvailable: true
        )
        XCTAssertEqual(
            resolve(isEnabled: true, snapshot: snapshot, selectedMetrics: [.monthly]),
            .noData
        )
    }

    func testUnavailableKeyProviderWithoutKeyNeedsKey() {
        let snapshot = UsageQuotaSnapshot.unavailable(providerID: .opencodeGo, statusNote: "sign in to OpenCode Go")
        XCTAssertEqual(
            resolve(isEnabled: true, snapshot: snapshot, isKeyProvider: true, hasStoredKey: false),
            .needsKey
        )
    }

    func testUnavailableKeyProviderWithKeyIsUnavailable() {
        let snapshot = UsageQuotaSnapshot.unavailable(providerID: .openrouter, statusNote: "token expired")
        XCTAssertEqual(
            resolve(isEnabled: true, snapshot: snapshot, isKeyProvider: true, hasStoredKey: true),
            .unavailable
        )
    }

    func testUnavailableStandardProviderIsUnavailable() {
        let snapshot = UsageQuotaSnapshot.unavailable(providerID: .cursor, statusNote: "sign in")
        XCTAssertEqual(
            resolve(isEnabled: true, snapshot: snapshot),
            .unavailable
        )
    }

    func testShowsPillOnlyForExceptionStates() {
        XCTAssertFalse(QuotaProviderStatus.hidden.showsPill)
        XCTAssertFalse(QuotaProviderStatus.inStrip.showsPill)
        XCTAssertTrue(QuotaProviderStatus.checking.showsPill)
        XCTAssertTrue(QuotaProviderStatus.noData.showsPill)
        XCTAssertTrue(QuotaProviderStatus.needsKey.showsPill)
        XCTAssertTrue(QuotaProviderStatus.unavailable.showsPill)
    }
}
