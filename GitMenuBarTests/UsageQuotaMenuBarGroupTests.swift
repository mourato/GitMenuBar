@testable import GitMenuBar
import XCTest

/// Compact-strip group and eligibility contract: which providers reach the
/// menu bar, what each group transports, and how value style and pace reach
/// the Line readings.
final class UsageQuotaMenuBarGroupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func window(
        remainingPercent: Int,
        elapsedFraction: Double,
        durationSeconds: Int = 10000
    ) -> UsageWindow {
        let duration = TimeInterval(durationSeconds)
        return UsageWindow(
            remainingPercent: remainingPercent,
            resetAt: now.addingTimeInterval(duration * (1 - elapsedFraction)),
            label: "5h",
            durationSeconds: durationSeconds
        )
    }

    @MainActor
    func testMenuReadingNamesAnExhaustedWeeklyQuota() throws {
        let suiteName = "UsageQuotaMenuBarGroupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults, keyStore: InMemoryAIAPIKeyStore())
        let snapshot = UsageQuotaSnapshot(
            providerID: .antigravity,
            displayName: "Antigravity",
            sessionWindow: nil,
            weeklyWindow: UsageWindow(
                remainingPercent: 0,
                resetAt: nil,
                label: "Weekly",
                durationSeconds: 7 * 86400
            ),
            isAvailable: true
        )

        let reading = try XCTUnwrap(
            UsageQuotaMenuPresentation.value(
                for: .weekly,
                snapshot: snapshot,
                valueStyle: preferences.valueStyle
            )
        )

        XCTAssertEqual(reading.value, "Exhausted")
        XCTAssertEqual(reading.compactValue, "Exhausted")
    }

    @MainActor
    func testMenuBarHidesWeeklyExhaustionAndRestoresProviderAfterRefresh() throws {
        let suiteName = "UsageQuotaMenuBarGroupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults, keyStore: InMemoryAIAPIKeyStore())
        preferences.setSelectedMetrics([.session], for: .codex)

        for style in UsageQuotaPresentationPreferences.ValueStyle.allCases {
            preferences.valueStyle = style
            for weeklyRemaining in [0, 1, 100] {
                for sessionRemaining in [0, 75] {
                    let snapshot = UsageQuotaSnapshot(
                        providerID: .codex,
                        displayName: "Codex",
                        sessionWindow: UsageWindow(remainingPercent: sessionRemaining, resetAt: nil, label: "5h"),
                        weeklyWindow: UsageWindow(remainingPercent: weeklyRemaining, resetAt: nil, label: "7d"),
                        isAvailable: true
                    )
                    let groups = UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences)
                    XCTAssertEqual(groups.map(\.providerID), weeklyRemaining == 0 ? [] : [.codex])
                    XCTAssertEqual(
                        UsageQuotaMenuPresentation.value(for: .weekly, snapshot: snapshot, valueStyle: style)?.compactValue,
                        weeklyRemaining == 0 ? "Exhausted" : (style == .used ? "\(100 - weeklyRemaining)%" : "\(weeklyRemaining)%")
                    )
                }
            }
        }
    }

    @MainActor
    func testModelOnlyProviderAppearsInMenuBar() throws {
        let suiteName = "UsageQuotaMenuBarGroupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults, keyStore: InMemoryAIAPIKeyStore())
        let snapshot = UsageQuotaSnapshot(
            providerID: .antigravity,
            displayName: "Antigravity",
            sessionWindow: nil,
            weeklyWindow: nil,
            modelWindows: [UsageWindow(remainingPercent: 45, resetAt: nil, label: "Gemini")],
            isAvailable: true
        )

        let group = try XCTUnwrap(UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences)
            .first { $0.providerID == .antigravity })
        XCTAssertEqual(group.fractions, [0.45])
    }

    @MainActor
    func testLineGroupTransportsFillAndPaceFromEachSelectedWindow() throws {
        let preferences = try isolatedPreferences()
        preferences.setSelectedMetrics([.session, .weekly], for: .codex)
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: window(remainingPercent: 76, elapsedFraction: 0.46),
            weeklyWindow: window(remainingPercent: 22, elapsedFraction: 0.36),
            isAvailable: true
        )

        let group = try XCTUnwrap(
            UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences, now: now).first
        )

        XCTAssertEqual(group.readings.count, 2)
        XCTAssertEqual(try XCTUnwrap(group.readings[0].fraction), 0.76, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(group.readings[0].pacePercent), 54, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(group.readings[1].fraction), 0.22, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(group.readings[1].pacePercent), 64, accuracy: 0.001)
        XCTAssertFalse(group.readings[0].paceDeficit)
        XCTAssertTrue(group.readings[1].paceDeficit)
    }

    @MainActor
    func testLineGroupUsedStyleMirrorsFillButPaceStaysOnTheDisplayScale() throws {
        let preferences = try isolatedPreferences()
        preferences.setSelectedMetrics([.session], for: .codex)
        preferences.valueStyle = .used
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: window(remainingPercent: 22, elapsedFraction: 0.36),
            weeklyWindow: nil,
            isAvailable: true
        )

        let group = try XCTUnwrap(
            UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences, now: now).first
        )
        let reading = try XCTUnwrap(group.readings.first)

        XCTAssertEqual(try XCTUnwrap(reading.fraction), 0.78, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(reading.pacePercent), 36, accuracy: 0.001)
        XCTAssertEqual(reading.compactValue, "78%")
    }

    @MainActor
    func testLineGroupKeepsCreditsTextualWithNoFractionOrPace() throws {
        let preferences = try isolatedPreferences()
        preferences.setSelectedMetrics([.session, .credits], for: .codex)
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: window(remainingPercent: 50, elapsedFraction: 0.5),
            weeklyWindow: nil,
            creditValueText: "12.50 credits",
            isAvailable: true
        )

        let group = try XCTUnwrap(
            UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences, now: now).first
        )

        XCTAssertEqual(group.readings.count, 2)
        XCTAssertEqual(group.readings[1].compactValue, "12.50 credits")
        XCTAssertNil(group.readings[1].fraction)
        XCTAssertNil(group.readings[1].pacePercent)
        XCTAssertEqual(group.fractions, [0.5])
    }

    @MainActor
    func testLineGroupHidesPaceWhenThePreferenceIsOff() throws {
        let preferences = try isolatedPreferences()
        preferences.setSelectedMetrics([.session, .weekly], for: .codex)
        preferences.showsPace = false
        let snapshot = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: window(remainingPercent: 22, elapsedFraction: 0.36),
            weeklyWindow: window(remainingPercent: 76, elapsedFraction: 0.46),
            isAvailable: true
        )

        let group = try XCTUnwrap(
            UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences, now: now).first
        )

        XCTAssertEqual(group.readings.count, 2)
        XCTAssertTrue(group.readings.allSatisfy { $0.pacePercent == nil })
    }

    @MainActor
    func testLineGroupKeepsModelWindowFallbackAndItsOwnPace() throws {
        let preferences = try isolatedPreferences()
        let snapshot = UsageQuotaSnapshot(
            providerID: .antigravity,
            displayName: "Antigravity",
            sessionWindow: nil,
            weeklyWindow: nil,
            modelWindows: [window(remainingPercent: 22, elapsedFraction: 0.36)],
            isAvailable: true
        )

        let group = try XCTUnwrap(
            UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences, now: now).first
        )
        let reading = try XCTUnwrap(group.readings.first)

        XCTAssertEqual(group.readings.count, 1)
        XCTAssertEqual(try XCTUnwrap(reading.fraction), 0.22, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(reading.pacePercent), 64, accuracy: 0.001)
    }

    @MainActor
    private func isolatedPreferences() throws -> UsageQuotaPresentationPreferences {
        let suiteName = "UsageQuotaMenuBarGroupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return UsageQuotaPresentationPreferences(
            defaults: defaults,
            keyStore: InMemoryAIAPIKeyStore()
        )
    }
}
