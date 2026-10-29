@testable import GitMenuBar
import XCTest

final class UsageQuotaDotsCardTests: XCTestCase {
    func testFilledSegments() {
        XCTAssertEqual(UsageQuotaDotsCard.filledSegments(displayPercent: 0), 0)
        XCTAssertEqual(UsageQuotaDotsCard.filledSegments(displayPercent: -5), 0)
        XCTAssertEqual(UsageQuotaDotsCard.filledSegments(displayPercent: 8), 1)
        XCTAssertEqual(UsageQuotaDotsCard.filledSegments(displayPercent: 47), 2)
        XCTAssertEqual(UsageQuotaDotsCard.filledSegments(displayPercent: 63), 3)
        XCTAssertEqual(UsageQuotaDotsCard.filledSegments(displayPercent: 85), 4)
        XCTAssertEqual(UsageQuotaDotsCard.filledSegments(displayPercent: 94), 5)
        XCTAssertEqual(UsageQuotaDotsCard.filledSegments(displayPercent: 100), 5)
    }

    func testRowAlertLevelFollowsConfiguredThresholds() {
        let thresholds = [50, 80]
        func level(remaining: Int) -> UsageQuotaAlertLevel {
            UsageQuotaDotsCard.RowData(
                title: "Session",
                countdown: nil,
                remainingPercent: remaining,
                thresholds: thresholds
            ).alertLevel
        }
        // Remaining 55% is 45% used, 40% is 60% used, 15% is 85% used.
        XCTAssertEqual(level(remaining: 55), .normal)
        XCTAssertEqual(level(remaining: 40), .warning)
        XCTAssertEqual(level(remaining: 15), .error)
    }

    func testPillText() {
        XCTAssertEqual(
            UsageQuotaDotsCard.pillText(plan: "Pro", intervalChip: "5h", resetCredits: 3),
            "Pro · 3 resets"
        )
        XCTAssertEqual(
            UsageQuotaDotsCard.pillText(plan: "Pro", intervalChip: "5h", resetCredits: 1),
            "Pro · 1 reset"
        )
        XCTAssertEqual(
            UsageQuotaDotsCard.pillText(plan: "Pro", intervalChip: "5h", resetCredits: nil),
            "Pro"
        )
        XCTAssertEqual(
            UsageQuotaDotsCard.pillText(plan: nil, intervalChip: "7d", resetCredits: nil),
            "7d"
        )
        XCTAssertEqual(
            UsageQuotaDotsCard.pillText(plan: nil, intervalChip: nil, resetCredits: 2),
            "2 resets"
        )
        XCTAssertNil(UsageQuotaDotsCard.pillText(plan: nil, intervalChip: nil, resetCredits: nil))
        XCTAssertNil(UsageQuotaDotsCard.pillText(plan: nil, intervalChip: nil, resetCredits: 0))
    }

    func testBareCountdown() {
        let now = Date()
        XCTAssertEqual(
            UsageQuotaDotsCard.bareCountdown(until: now.addingTimeInterval(5400), now: now),
            "1h 30m"
        )
        XCTAssertNil(UsageQuotaDotsCard.bareCountdown(until: nil, now: now))
        XCTAssertNil(UsageQuotaDotsCard.bareCountdown(until: now.addingTimeInterval(-60), now: now))
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
