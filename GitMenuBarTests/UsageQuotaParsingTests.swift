@testable import GitMenuBar
import XCTest

final class UsageQuotaParsingTests: XCTestCase {
    func testRemainingPercentFromUsed() {
        XCTAssertEqual(CodexUsageParsing.remainingPercent(fromUsed: 0), 100)
        XCTAssertEqual(CodexUsageParsing.remainingPercent(fromUsed: 100), 0)
        XCTAssertEqual(CodexUsageParsing.remainingPercent(fromUsed: 30), 70)
        XCTAssertEqual(CodexUsageParsing.remainingPercent(fromUsed: 30.4), 70)
        XCTAssertEqual(CodexUsageParsing.remainingPercent(fromUsed: 150), 0)
        XCTAssertEqual(CodexUsageParsing.remainingPercent(fromUsed: -10), 100)
    }

    func testDoubleValueCoercions() {
        XCTAssertEqual(CodexUsageParsing.doubleValue(5), 5)
        XCTAssertEqual(CodexUsageParsing.doubleValue(5.5), 5.5)
        XCTAssertEqual(CodexUsageParsing.doubleValue("5.5"), 5.5)
        XCTAssertNil(CodexUsageParsing.doubleValue("not a number"))
        XCTAssertNil(CodexUsageParsing.doubleValue(nil))
    }

    func testCodexAPIWindow() {
        let (used, reset, duration) = CodexUsageParsing.codexAPIWindow([
            "used_percent": 42.0,
            "reset_at": 1_700_000_000.0,
            "limit_window_seconds": 604_800
        ])
        XCTAssertEqual(used, 42.0)
        XCTAssertEqual(reset, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(duration, 604_800)

        let (usedInt, _, _) = CodexUsageParsing.codexAPIWindow(["used_percent": 30])
        XCTAssertEqual(usedInt, 30)

        let (none, noReset, noDuration) = CodexUsageParsing.codexAPIWindow(nil)
        XCTAssertNil(none)
        XCTAssertNil(noReset)
        XCTAssertNil(noDuration)
    }

    func testSnapshotFromUsageAPI() {
        let root: [String: Any] = [
            "rate_limit": [
                "primary_window": [
                    "used_percent": 34.0,
                    "reset_at": 1_700_000_000.0,
                    "limit_window_seconds": 18000
                ],
                "secondary_window": [
                    "used_percent": 50.0,
                    "reset_at": 1_800_000_000.0,
                    "limit_window_seconds": 604_800
                ]
            ],
            "credits": [
                "has_credits": true,
                "balance": "12.5"
            ]
        ]

        let snapshot = CodexUsageParsing.snapshot(fromUsageAPI: root)

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 66)
        XCTAssertEqual(snapshot?.sessionWindow?.intervalChip, "5h")
        XCTAssertEqual(snapshot?.weeklyWindow?.remainingPercent, 50)
        XCTAssertEqual(snapshot?.weeklyWindow?.intervalChip, "7d")
        XCTAssertEqual(snapshot?.creditValueText, "12.5 credits")
        XCTAssertEqual(snapshot?.statusNote, "chatgpt usage api")
    }

    func testResetCreditsAvailableCount() {
        let json = """
        {"available_count":2,"credits":[{"id":"a"},{"id":"b","expires_at":"2099-01-01T00:00:00Z"}]}
        """
        XCTAssertEqual(CodexUsageParsing.resetCreditsAvailable(from: Data(json.utf8)), 2)

        let expiredOnly = """
        {"credits":[{"id":"old","expires_at":"2000-01-01T00:00:00Z"}]}
        """
        XCTAssertEqual(CodexUsageParsing.resetCreditsAvailable(from: Data(expiredOnly.utf8)), 0)
    }

    func testIntervalChipAndDayScaleCountdown() {
        XCTAssertEqual(UsageQuotaFormatting.intervalChip(durationSeconds: 5 * 3600), "5h")
        XCTAssertEqual(UsageQuotaFormatting.intervalChip(durationSeconds: 7 * 86400), "7d")
        let now = Date()
        XCTAssertEqual(
            UsageQuotaFormatting.resetCountdown(until: now.addingTimeInterval(2 * 86400 + 3 * 3600), now: now),
            "2d 3h"
        )
    }

    func testResetClockTimeUsesLocaleTimeOnly() throws {
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 10, minute: 0)))
        let resetAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 18, minute: 27)))

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let expected = formatter.string(from: resetAt)

        XCTAssertEqual(
            UsageQuotaFormatting.resetClockTime(until: resetAt, locale: locale, now: now),
            expected
        )
    }

    func testResetClockTime24HourLocale() throws {
        let locale = Locale(identifier: "en_GB")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 10, minute: 0)))
        let resetAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 18, minute: 27)))

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let expected = formatter.string(from: resetAt)

        XCTAssertEqual(
            UsageQuotaFormatting.resetClockTime(until: resetAt, locale: locale, now: now),
            expected
        )
        XCTAssertFalse(expected.contains("AM"))
        XCTAssertFalse(expected.contains("PM"))
    }

    func testResetClockTimeMissingOrPast() {
        let now = Date()
        XCTAssertEqual(UsageQuotaFormatting.resetClockTime(until: nil, now: now), "—")
        XCTAssertEqual(
            UsageQuotaFormatting.resetClockTime(until: now.addingTimeInterval(-60), now: now),
            "—"
        )
    }

    func testCreditsUnlimitedAndMissing() {
        let unlimitedRoot: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": 0.0, "reset_at": 1_700_000_000.0]
            ],
            "credits": ["unlimited": true]
        ]
        XCTAssertEqual(CodexUsageParsing.snapshot(fromUsageAPI: unlimitedRoot)?.creditValueText, "Unlimited")

        let noCreditsRoot: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": 0.0, "reset_at": 1_700_000_000.0]
            ],
            "credits": ["has_credits": false]
        ]
        XCTAssertNil(CodexUsageParsing.snapshot(fromUsageAPI: noCreditsRoot)?.creditValueText)
    }

    func testSnapshotFromSessionsJSONL() {
        let resetAt = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let weeklyResetAt = Int(Date().addingTimeInterval(86400).timeIntervalSince1970)
        let jsonl = """
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{\
        "primary":{"used_percent":20,"resets_at":\(resetAt),"window_minutes":300},\
        "secondary":{"used_percent":40,"resets_at":\(weeklyResetAt),"window_minutes":10080}}}}
        """

        let snapshot = CodexUsageParsing.snapshot(fromSessionsJSONL: jsonl)

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 80)
        XCTAssertEqual(snapshot?.sessionWindow?.intervalChip, "5h")
        XCTAssertEqual(snapshot?.weeklyWindow?.remainingPercent, 60)
        XCTAssertEqual(snapshot?.weeklyWindow?.intervalChip, "7d")
        XCTAssertEqual(snapshot?.statusNote, "local .codex sessions")
    }

    func testSnapshotFromEmptySessionsJSONLReturnsNil() {
        XCTAssertNil(CodexUsageParsing.snapshot(fromSessionsJSONL: ""))
        XCTAssertNil(CodexUsageParsing.snapshot(fromSessionsJSONL: "{\"type\":\"other\"}\n"))
    }

    func testJWTExpiry() {
        let token = Self.makeJWT(payload: ["exp": 2_000_000_000])
        XCTAssertEqual(CodexUsageParsing.jwtExpiry(token), Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertNil(CodexUsageParsing.jwtExpiry("garbage"))
    }

    private static func makeJWT(payload: [String: Any]) -> String {
        let header = Data("{}".utf8).base64EncodedString()
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return "invalid.invalid.invalid"
        }
        let payloadPart = payloadData.base64EncodedString()
        return "\(header).\(payloadPart).signature"
    }
}
