@testable import GitMenuBar
import XCTest

final class ClaudeCodeUsageTests: XCTestCase {
    func testParsesLatestFiveHourAndSevenDayEvents() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let text = """
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.25,"resetsAt":1800003600}}
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"seven_day","utilization":42,"resetsAt":"2030-01-20T12:00:00Z"}}
        """

        let snapshot = try XCTUnwrap(ClaudeCodeUsageParsing.snapshot(fromJSONL: text, now: now))

        XCTAssertEqual(snapshot.providerID, .claudeCode)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 75)
        XCTAssertEqual(snapshot.sessionWindow?.intervalChip, "5h")
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 58)
        XCTAssertEqual(snapshot.weeklyWindow?.intervalChip, "7d")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testKeepsNewestReadingForEachWindow() throws {
        let text = """
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.80,"resetsAt":1800001000}}
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.20,"resetsAt":1800002000}}
        """

        let snapshot = try XCTUnwrap(ClaudeCodeUsageParsing.snapshot(fromJSONL: text))
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 80)
        XCTAssertEqual(snapshot.sessionWindow?.resetAt, Date(timeIntervalSince1970: 1_800_002_000))
    }

    func testIgnoresEventsWithoutUtilization() {
        let text = """
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","resetsAt":1800003600}}
        """

        XCTAssertNil(ClaudeCodeUsageParsing.snapshot(fromJSONL: text))
    }
}
