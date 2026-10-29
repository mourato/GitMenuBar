@testable import GitMenuBar
import XCTest

final class UsageQuotaFormattingTests: XCTestCase {
    func testAlertLevelStaysNormalBelowFirstThreshold() {
        // 62% left is 38% used: below the 50 threshold.
        XCTAssertEqual(
            UsageQuotaFormatting.alertLevel(remainingPercent: 62, thresholds: [50, 80]),
            .normal
        )
    }

    func testAlertLevelWarnsAtFirstThresholdAndErrorsAtSecond() {
        // Thresholds compare against used percent: 50% used warns, 80% used errors.
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 50, thresholds: [50, 80]), .warning)
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 30, thresholds: [50, 80]), .warning)
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 20, thresholds: [50, 80]), .error)
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 0, thresholds: [50, 80]), .error)
    }

    func testAlertLevelUsesConfiguredValues() {
        let thresholds = [30, 60]
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 71, thresholds: thresholds), .normal)
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 70, thresholds: thresholds), .warning)
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 41, thresholds: thresholds), .warning)
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 40, thresholds: thresholds), .error)
    }

    func testAlertLevelWithoutThresholdsStaysNormal() {
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 0, thresholds: []), .normal)
    }

    func testAlertLevelWithSingleThresholdWarnsButNeverErrors() {
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 40, thresholds: [60]), .warning)
        XCTAssertEqual(UsageQuotaFormatting.alertLevel(remainingPercent: 0, thresholds: [60]), .warning)
    }
}
