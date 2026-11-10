@testable import GitMenuBar
import XCTest

/// Contract for the quota settings status pill: the same snapshot rules that
/// drive the menu-bar strip must drive the per-provider status text.
final class QuotaProviderStatusTests: XCTestCase {
    private func window() -> UsageWindow {
        UsageWindow(remainingPercent: 62, resetAt: nil, label: "5h")
    }

    func testDisabledProviderIsHidden() {
        XCTAssertEqual(
            QuotaProviderStatus.resolve(isEnabled: false, snapshot: nil, isKeyProvider: false, hasStoredKey: false),
            .hidden
        )
    }

    func testEnabledProviderWithoutSnapshotIsChecking() {
        XCTAssertEqual(
            QuotaProviderStatus.resolve(isEnabled: true, snapshot: nil, isKeyProvider: false, hasStoredKey: false),
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
        XCTAssertEqual(
            QuotaProviderStatus.resolve(isEnabled: true, snapshot: snapshot, isKeyProvider: false, hasStoredKey: false),
            .inStrip
        )
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
        XCTAssertEqual(
            QuotaProviderStatus.resolve(isEnabled: true, snapshot: snapshot, isKeyProvider: false, hasStoredKey: false),
            .inStrip
        )
    }

    func testAvailableSnapshotWithoutWindowsIsNoData() {
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: nil,
            weeklyWindow: nil,
            isAvailable: true
        )
        XCTAssertEqual(
            QuotaProviderStatus.resolve(isEnabled: true, snapshot: snapshot, isKeyProvider: false, hasStoredKey: false),
            .noData
        )
    }

    func testUnavailableKeyProviderWithoutKeyNeedsKey() {
        let snapshot = UsageQuotaSnapshot.unavailable(providerID: .opencodeGo, statusNote: "sign in to OpenCode Go")
        XCTAssertEqual(
            QuotaProviderStatus.resolve(isEnabled: true, snapshot: snapshot, isKeyProvider: true, hasStoredKey: false),
            .needsKey
        )
    }

    func testUnavailableKeyProviderWithKeyIsUnavailable() {
        let snapshot = UsageQuotaSnapshot.unavailable(providerID: .openrouter, statusNote: "token expired")
        XCTAssertEqual(
            QuotaProviderStatus.resolve(isEnabled: true, snapshot: snapshot, isKeyProvider: true, hasStoredKey: true),
            .unavailable
        )
    }

    func testUnavailableStandardProviderIsUnavailable() {
        let snapshot = UsageQuotaSnapshot.unavailable(providerID: .cursor, statusNote: "sign in")
        XCTAssertEqual(
            QuotaProviderStatus.resolve(isEnabled: true, snapshot: snapshot, isKeyProvider: false, hasStoredKey: false),
            .unavailable
        )
    }
}
