@testable import GitMenuBar
import XCTest

final class UsageQuotaLineCardTests: XCTestCase {
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

    private func reading(
        remainingPercent: Int,
        elapsedFraction: Double,
        showUsed: Bool,
        showsPace: Bool = true
    ) -> UsageQuotaPace.Reading {
        UsageQuotaPace.reading(
            for: window(remainingPercent: remainingPercent, elapsedFraction: elapsedFraction),
            showUsed: showUsed,
            thresholds: [50, 80],
            workdaysPerWeek: 5,
            showPace: showsPace,
            now: now
        )
    }

    func testRowAlertLevelFollowsConfiguredThresholds() {
        let thresholds = [50, 80]
        func level(remaining: Int) -> UsageQuotaAlertLevel {
            UsageQuotaLineCard.RowData(
                title: "Session",
                window: UsageWindow(remainingPercent: remaining, resetAt: nil, label: "Session"),
                thresholds: thresholds,
                kind: .session
            ).alertLevel
        }
        // Remaining 55% is 45% used, 40% is 60% used, 15% is 85% used.
        XCTAssertEqual(level(remaining: 55), .normal)
        XCTAssertEqual(level(remaining: 40), .warning)
        XCTAssertEqual(level(remaining: 15), .error)
    }

    func testWeeklyZeroRowIsAlwaysErrorLevel() {
        let row = UsageQuotaLineCard.RowData(
            title: "Weekly",
            window: UsageWindow(remainingPercent: 0, resetAt: nil, label: "Weekly"),
            thresholds: [],
            kind: .weekly
        )

        XCTAssertTrue(row.isExhausted)
        XCTAssertEqual(row.alertLevel, .error)
    }

    func testRemainingDeficitFillsActualValueAndHatchesToExpectedMarker() throws {
        let reading = reading(remainingPercent: 22, elapsedFraction: 0.36, showUsed: false)

        XCTAssertEqual(reading.fillPercent, 22, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(reading.pacePercent), 64, accuracy: 0.001)
        XCTAssertTrue(reading.paceDeficit)

        let hatch = try XCTUnwrap(UsageQuotaLineMeter.hatchRange(
            fillPercent: reading.fillPercent,
            pacePercent: reading.pacePercent,
            paceDeficit: reading.paceDeficit
        ))
        XCTAssertEqual(hatch.lowerBound, 22, accuracy: 0.001)
        XCTAssertEqual(hatch.upperBound, 64, accuracy: 0.001)
    }

    func testUsedDeficitHatchesBetweenExpectedMarkerAndFill() throws {
        let reading = reading(remainingPercent: 22, elapsedFraction: 0.36, showUsed: true)

        XCTAssertEqual(reading.fillPercent, 78, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(reading.pacePercent), 36, accuracy: 0.001)
        XCTAssertTrue(reading.paceDeficit)

        let hatch = try XCTUnwrap(UsageQuotaLineMeter.hatchRange(
            fillPercent: reading.fillPercent,
            pacePercent: reading.pacePercent,
            paceDeficit: reading.paceDeficit
        ))
        XCTAssertEqual(hatch.lowerBound, 36, accuracy: 0.001)
        XCTAssertEqual(hatch.upperBound, 78, accuracy: 0.001)
    }

    func testReserveAndOnTrackHaveNoHatch() {
        // 76% left with 54% expected left: consumption is behind pace, not a deficit.
        let reserve = reading(remainingPercent: 76, elapsedFraction: 0.46, showUsed: false)
        XCTAssertEqual(reserve.fillPercent, 76, accuracy: 0.001)
        XCTAssertEqual(reserve.pacePercent ?? -1, 54, accuracy: 0.001)
        XCTAssertFalse(reserve.paceDeficit)
        XCTAssertNil(UsageQuotaLineMeter.hatchRange(
            fillPercent: reserve.fillPercent,
            pacePercent: reserve.pacePercent,
            paceDeficit: reserve.paceDeficit
        ))

        // On-track readings hide the marker entirely, so a stale deficit flag cannot hatch.
        let onTrack = reading(remainingPercent: 51, elapsedFraction: 0.5, showUsed: false)
        XCTAssertNil(onTrack.pacePercent)
        XCTAssertNil(UsageQuotaLineMeter.hatchRange(
            fillPercent: onTrack.fillPercent,
            pacePercent: onTrack.pacePercent,
            paceDeficit: true
        ))
    }

    func testHatchGeometryClampsToBar() throws {
        let hatch = try XCTUnwrap(UsageQuotaLineMeter.hatchRange(
            fillPercent: -5,
            pacePercent: 140,
            paceDeficit: true
        ))
        XCTAssertEqual(hatch.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(hatch.upperBound, 100, accuracy: 0.001)
        XCTAssertNil(UsageQuotaLineMeter.hatchRange(
            fillPercent: 40,
            pacePercent: 40,
            paceDeficit: true
        ))
    }

    func testHiddenPaceStillCarriesNoMarkerOrHatch() {
        let reading = reading(remainingPercent: 22, elapsedFraction: 0.36, showUsed: false, showsPace: false)

        XCTAssertNil(reading.pacePercent)
        XCTAssertNil(reading.paceLeftText)
        XCTAssertNil(reading.paceRightText)
        XCTAssertNil(UsageQuotaLineMeter.hatchRange(
            fillPercent: reading.fillPercent,
            pacePercent: reading.pacePercent,
            paceDeficit: reading.paceDeficit
        ))
    }

    func testRowsShowOnlyPercentUnlessWeeklyQuotaIsExhausted() {
        XCTAssertEqual(
            UsageQuotaFormatting.compactDisplayValueText(remainingPercent: 22, kind: .session, showUsed: false),
            "22%"
        )
        XCTAssertEqual(
            UsageQuotaFormatting.compactDisplayValueText(remainingPercent: 22, kind: .session, showUsed: true),
            "78%"
        )
        XCTAssertEqual(
            UsageQuotaFormatting.compactDisplayValueText(remainingPercent: 0, kind: .weekly, showUsed: false),
            "Exhausted"
        )
    }

    func testRowAccessibilityValueKeepsDirectionResetAndPace() {
        let reading = reading(remainingPercent: 22, elapsedFraction: 0.36, showUsed: false)

        let value = UsageQuotaLineCard.rowAccessibilityValue(reading: reading, isExhausted: false)
        XCTAssertTrue(value.hasPrefix("22% left, Resets in "))
        XCTAssertTrue(value.contains("42% in deficit"))
        XCTAssertFalse(value.contains("left left"))
    }

    func testExhaustedRowAccessibilityValueOmitsPercentDirection() {
        let reading = UsageQuotaPace.reading(
            for: UsageWindow(remainingPercent: 0, resetAt: nil, label: "Weekly"),
            showUsed: false,
            thresholds: [50, 80],
            workdaysPerWeek: 5,
            showPace: true,
            now: now
        )

        XCTAssertEqual(
            UsageQuotaLineCard.rowAccessibilityValue(reading: reading, isExhausted: true),
            "quota exhausted"
        )
    }

    func testPillTextKeepsPlanAndResetsOnly() {
        XCTAssertEqual(
            UsageQuotaLineCard.pillText(plan: "Pro", resetCredits: 3),
            "Pro · 3 resets"
        )
        XCTAssertEqual(
            UsageQuotaLineCard.pillText(plan: "Pro", resetCredits: 1),
            "Pro · 1 reset"
        )
        XCTAssertEqual(
            UsageQuotaLineCard.pillText(plan: "Pro", resetCredits: nil),
            "Pro"
        )
        XCTAssertEqual(
            UsageQuotaLineCard.pillText(plan: nil, resetCredits: 2),
            "2 resets"
        )
        XCTAssertNil(UsageQuotaLineCard.pillText(plan: nil, resetCredits: nil))
        XCTAssertNil(UsageQuotaLineCard.pillText(plan: nil, resetCredits: 0))
    }

    func testHeaderAccessibilityTextAnnouncesProviderPlanAndResetsOnce() {
        XCTAssertEqual(
            UsageQuotaLineCard.headerAccessibilityText(
                displayName: "Codex",
                pillText: UsageQuotaLineCard.pillText(plan: "Plus", resetCredits: 1),
                isStale: false
            ),
            "Codex, Plus, 1 reset"
        )
        XCTAssertEqual(
            UsageQuotaLineCard.headerAccessibilityText(
                displayName: "Codex",
                pillText: UsageQuotaLineCard.pillText(plan: "Plus", resetCredits: 3),
                isStale: true
            ),
            "Codex, Plus, 3 resets, Outdated"
        )
    }

    func testHeaderAccessibilityTextOmitsMissingParts() {
        XCTAssertEqual(
            UsageQuotaLineCard.headerAccessibilityText(
                displayName: "Codex",
                pillText: UsageQuotaLineCard.pillText(plan: nil, resetCredits: 1),
                isStale: false
            ),
            "Codex, 1 reset"
        )
        XCTAssertEqual(
            UsageQuotaLineCard.headerAccessibilityText(
                displayName: "Codex",
                pillText: UsageQuotaLineCard.pillText(plan: "Plus", resetCredits: nil),
                isStale: false
            ),
            "Codex, Plus"
        )
        XCTAssertEqual(
            UsageQuotaLineCard.headerAccessibilityText(
                displayName: "Codex",
                pillText: nil,
                isStale: false
            ),
            "Codex"
        )
        XCTAssertEqual(
            UsageQuotaLineCard.headerAccessibilityText(
                displayName: "Codex",
                pillText: nil,
                isStale: true
            ),
            "Codex, Outdated"
        )
    }

    func testAmountText() {
        XCTAssertEqual(UsageQuotaCostScanner.amountText(89.27), "$89.27")
        XCTAssertEqual(UsageQuotaCostScanner.amountText(nil), "—")
    }

    func testMonthLabel() {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 12
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
        XCTAssertEqual(
            UsageQuotaCostScanner.monthLabel(for: date, locale: Locale(identifier: "en_US_POSIX")),
            "Oct"
        )
    }

    func testPlanDisplayNames() {
        XCTAssertEqual(UsageQuotaPlanNaming.display("pro"), "Pro")
        XCTAssertEqual(UsageQuotaPlanNaming.display("team"), "Team")
        XCTAssertNil(UsageQuotaPlanNaming.display(nil))
        XCTAssertNil(UsageQuotaPlanNaming.display("  "))
    }

    func testCursorPlanNames() {
        XCTAssertEqual(UsageQuotaPlanNaming.cursor("pro"), "Pro")
        XCTAssertEqual(UsageQuotaPlanNaming.cursor("team"), "Team")
        XCTAssertEqual(UsageQuotaPlanNaming.cursor("pro_plus"), "Pro+")
        XCTAssertEqual(UsageQuotaPlanNaming.cursor("free_trial"), "Pro Trial")
        XCTAssertNil(UsageQuotaPlanNaming.cursor(nil))
    }

    func testCursorSnapshotCarriesPlan() {
        let snapshot = CursorUsageParsing.snapshot(fromUsageSummary: [
            "billingCycleEnd": "2026-11-01T00:00:00Z",
            "individualUsage": ["plan": ["used": 10.0, "limit": 100.0]],
            "membershipType": "pro"
        ])
        XCTAssertEqual(snapshot?.planText, "Pro")
    }

    func testCodexPlanTypeFromJWT() {
        let payload = #"{"https://api.openai.com/auth":{"chatgpt_plan_type":"pro"}}"#
        let token = "h.\(Data(payload.utf8).base64EncodedString()).s"
        XCTAssertEqual(
            CodexUsageParsing.planType(fromAuth: ["tokens": ["id_token": token]]),
            "pro"
        )
        XCTAssertEqual(
            CodexUsageParsing.planType(fromAuth: ["chatgpt_plan_type": "team"]),
            "team"
        )
        XCTAssertNil(CodexUsageParsing.planType(fromAuth: [:]))
    }
}
