@testable import GitMenuBar
import XCTest

final class UsageQuotaPaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func window(remainingPercent: Int, elapsedFraction: Double, durationSeconds: Int) -> UsageWindow {
        let duration = TimeInterval(durationSeconds)
        let resetAt = now.addingTimeInterval(duration * (1 - elapsedFraction))
        return UsageWindow(
            remainingPercent: remainingPercent,
            resetAt: resetAt,
            label: "5h",
            durationSeconds: durationSeconds
        )
    }

    func testBehindPaceReportsReserveAndPaceOnTop() throws {
        let pace = try XCTUnwrap(UsageQuotaPace.pace(
            for: window(remainingPercent: 60, elapsedFraction: 0.5, durationSeconds: 18000),
            now: now
        ))

        XCTAssertEqual(pace.stage, .behind)
        XCTAssertEqual(pace.paceOnTop, true)
        XCTAssertEqual(pace.expectedUsedPercent, 50, accuracy: 0.001)
        XCTAssertEqual(UsageQuotaPace.leftLabel(for: pace), "10% in reserve")
    }

    func testAheadPaceReportsDeficit() throws {
        let pace = try XCTUnwrap(UsageQuotaPace.pace(
            for: window(remainingPercent: 30, elapsedFraction: 0.5, durationSeconds: 18000),
            now: now
        ))

        XCTAssertEqual(pace.stage, .ahead)
        XCTAssertEqual(pace.paceOnTop, false)
        XCTAssertEqual(UsageQuotaPace.leftLabel(for: pace), "20% in deficit")
    }

    func testOnTrackPace() throws {
        let pace = try XCTUnwrap(UsageQuotaPace.pace(
            for: window(remainingPercent: 51, elapsedFraction: 0.5, durationSeconds: 18000),
            now: now
        ))

        XCTAssertEqual(pace.stage, .onTrack)
        XCTAssertEqual(UsageQuotaPace.leftLabel(for: pace), "On pace")
    }

    func testPaceNilWhenWindowUnknown() {
        let noReset = UsageWindow(remainingPercent: 60, resetAt: nil, label: "5h", durationSeconds: 18000)
        XCTAssertNil(UsageQuotaPace.pace(for: noReset, now: now))

        let noDuration = UsageWindow(
            remainingPercent: 60,
            resetAt: now.addingTimeInterval(9000),
            label: "5h"
        )
        XCTAssertNil(UsageQuotaPace.pace(for: noDuration, now: now))

        let pastReset = UsageWindow(
            remainingPercent: 60,
            resetAt: now.addingTimeInterval(-10),
            label: "5h",
            durationSeconds: 18000
        )
        XCTAssertNil(UsageQuotaPace.pace(for: pastReset, now: now))

        let exhausted = window(remainingPercent: 0, elapsedFraction: 0.5, durationSeconds: 18000)
        XCTAssertNil(UsageQuotaPace.pace(for: exhausted, now: now))

        let justStarted = window(remainingPercent: 99, elapsedFraction: 0.001, durationSeconds: 18000)
        XCTAssertNil(UsageQuotaPace.pace(for: justStarted, now: now))
    }

    func testLastsUntilResetWhenUnderPace() throws {
        let pace = try XCTUnwrap(UsageQuotaPace.pace(
            for: window(remainingPercent: 90, elapsedFraction: 0.9, durationSeconds: 10000),
            now: now
        ))

        XCTAssertEqual(pace.willLastToReset, true)
        XCTAssertEqual(UsageQuotaPace.rightLabel(for: pace, now: now), "Lasts until reset")
    }

    func testRunsOutWhenOverPace() throws {
        let pace = try XCTUnwrap(UsageQuotaPace.pace(
            for: window(remainingPercent: 10, elapsedFraction: 0.5, durationSeconds: 10000),
            now: now
        ))

        XCTAssertEqual(pace.willLastToReset, false)
        XCTAssertNotNil(pace.etaSeconds)
        XCTAssertTrue(UsageQuotaPace.rightLabel(for: pace, now: now)?.hasPrefix("Runs out in ") ?? false)
    }

    func testWarningMarkersMirrorWhenShowingLeft() {
        XCTAssertEqual(
            UsageQuotaPace.warningMarkerPercents(thresholds: [50, 80], showUsed: true),
            [50, 80]
        )
        XCTAssertEqual(
            UsageQuotaPace.warningMarkerPercents(thresholds: [50, 80], showUsed: false),
            [20, 50]
        )
    }

    func testWarningMarkersDropEdges() {
        XCTAssertEqual(
            UsageQuotaPace.warningMarkerPercents(thresholds: [0, 100], showUsed: true),
            []
        )
    }

    func testWorkdayMarkersSplitWeeklyWindow() {
        XCTAssertEqual(
            UsageQuotaPace.workdayMarkerPercents(workdaysPerWeek: 5, durationSeconds: 7 * 86400),
            [20, 40, 60, 80]
        )
        XCTAssertEqual(
            UsageQuotaPace.workdayMarkerPercents(workdaysPerWeek: 5, durationSeconds: 18000),
            []
        )
        XCTAssertEqual(
            UsageQuotaPace.workdayMarkerPercents(workdaysPerWeek: 1, durationSeconds: 7 * 86400),
            []
        )
        XCTAssertEqual(
            UsageQuotaPace.workdayMarkerPercents(workdaysPerWeek: 8, durationSeconds: 7 * 86400),
            []
        )
        XCTAssertEqual(
            UsageQuotaPace.workdayMarkerPercents(workdaysPerWeek: 5, durationSeconds: nil),
            []
        )
    }

    func testReadingHidesMarkerOnTrackButKeepsLabels() {
        let reading = UsageQuotaPace.reading(
            for: window(remainingPercent: 51, elapsedFraction: 0.5, durationSeconds: 18000),
            showUsed: false,
            thresholds: [50, 80],
            workdaysPerWeek: 5,
            showPace: true,
            now: now
        )

        XCTAssertNil(reading.pacePercent)
        XCTAssertFalse(reading.paceDeficit)
        XCTAssertEqual(reading.paceLeftText, "On pace")
        XCTAssertEqual(reading.paceRightText, "Lasts until reset")
    }

    func testReadingDeficitMarkerMirrorsWithValueStyle() {
        let ahead = window(remainingPercent: 60, elapsedFraction: 0.25, durationSeconds: 18000)
        let usedReading = UsageQuotaPace.reading(
            for: ahead,
            showUsed: true,
            thresholds: [50, 80],
            workdaysPerWeek: 5,
            showPace: true,
            now: now
        )
        let leftReading = UsageQuotaPace.reading(
            for: ahead,
            showUsed: false,
            thresholds: [50, 80],
            workdaysPerWeek: 5,
            showPace: true,
            now: now
        )

        XCTAssertEqual(usedReading.percentText, "40% used")
        XCTAssertEqual(leftReading.percentText, "60% left")
        XCTAssertTrue(usedReading.paceDeficit)
        XCTAssertEqual(usedReading.pacePercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(leftReading.pacePercent ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(usedReading.warningMarkerPercents, [50, 80])
        XCTAssertEqual(leftReading.warningMarkerPercents, [20, 50])
    }

    func testReadingOmitsPaceWhenHidden() {
        let reading = UsageQuotaPace.reading(
            for: window(remainingPercent: 30, elapsedFraction: 0.5, durationSeconds: 18000),
            showUsed: false,
            thresholds: [50, 80],
            workdaysPerWeek: 5,
            showPace: false,
            now: now
        )

        XCTAssertNil(reading.paceLeftText)
        XCTAssertNil(reading.paceRightText)
        XCTAssertNil(reading.pacePercent)
    }

    func testReadingResetAndDetailTexts() {
        let reading = UsageQuotaPace.reading(
            for: window(remainingPercent: 60, elapsedFraction: 0.5, durationSeconds: 18000),
            showUsed: false,
            thresholds: [50, 80],
            workdaysPerWeek: 5,
            showPace: true,
            now: now
        )

        XCTAssertEqual(reading.resetText, "Resets in 2h 30m")
        XCTAssertNotNil(reading.detailText)
        XCTAssertTrue(reading.detailText?.hasPrefix("Resets at ") ?? false)
    }

    func testSanitizedThresholds() {
        XCTAssertEqual(UsageQuotaPace.sanitizedThresholds([80, 50, 80, 0, 150]), [1, 50, 80, 99])
        XCTAssertEqual(UsageQuotaPace.sanitizedThresholds([]), [])
    }

    func testParseThresholds() {
        XCTAssertEqual(UsageQuotaPace.parseThresholds("50, 80"), [50, 80])
        XCTAssertEqual(UsageQuotaPace.parseThresholds("80 50"), [50, 80])
        XCTAssertNil(UsageQuotaPace.parseThresholds("nothing here"))
        XCTAssertEqual(UsageQuotaPace.parseThresholds(""), [])
        XCTAssertEqual(UsageQuotaPace.parseThresholds("  "), [])
    }

    func testRowTitle() {
        let timed = UsageWindow(
            remainingPercent: 60,
            resetAt: now.addingTimeInterval(9000),
            label: "5h",
            durationSeconds: 18000
        )
        let untimed = UsageWindow(remainingPercent: 42, resetAt: nil, label: "Credits")
        XCTAssertEqual(UsageQuotaPace.rowTitle(isSessionWindow: true, window: timed), "Session")
        XCTAssertEqual(UsageQuotaPace.rowTitle(isSessionWindow: true, window: untimed), "Credits")
        XCTAssertEqual(UsageQuotaPace.rowTitle(isSessionWindow: false, window: timed), "Weekly")
        XCTAssertEqual(UsageQuotaPace.rowTitle(isSessionWindow: false, window: untimed), "Credits")
    }
}
