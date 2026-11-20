@testable import GitMenuBar
import XCTest

final class UsageQuotaSummaryResolutionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let sessionThresholds = [50, 80]
    private let weeklyThresholds = [50, 80]

    private func window(
        remainingPercent: Int,
        elapsedFraction: Double = 0.36,
        durationSeconds: Int = 10000,
        label: String = "5h"
    ) -> UsageWindow {
        let duration = TimeInterval(durationSeconds)
        return UsageWindow(
            remainingPercent: remainingPercent,
            resetAt: now.addingTimeInterval(duration * (1 - elapsedFraction)),
            label: label,
            durationSeconds: durationSeconds
        )
    }

    private func snapshot(
        session: Int? = nil,
        weekly: Int? = nil,
        monthly: Int? = nil,
        models: [Int] = [],
        isStale: Bool = false
    ) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            sessionWindow: session.map {
                window(remainingPercent: $0, durationSeconds: 5 * 3600, label: "5h")
            },
            weeklyWindow: weekly.map { window(remainingPercent: $0, label: "7d") },
            tertiaryMonthlyWindow: monthly.map { window(remainingPercent: $0, label: "30-day") },
            modelWindows: models.enumerated().map { index, remaining in
                window(remainingPercent: remaining, label: "Model\(index)")
            },
            isAvailable: true,
            isStale: isStale
        )
    }

    private func resolve(
        _ snapshot: UsageQuotaSnapshot,
        sessionThresholds: [Int]? = nil,
        weeklyThresholds: [Int]? = nil
    ) -> UsageQuotaSummaryResolution? {
        UsageQuotaSummaryResolution.resolve(
            snapshot: snapshot,
            sessionThresholds: sessionThresholds ?? self.sessionThresholds,
            weeklyThresholds: weeklyThresholds ?? self.weeklyThresholds
        )
    }

    func testCriticalWeeklyWinsOverQuietSession() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 76, weekly: 22)))

        XCTAssertEqual(resolved.window.remainingPercent, 22)
        XCTAssertEqual(resolved.kind, .weekly)
        XCTAssertEqual(resolved.title, "Weekly")
        XCTAssertEqual(resolved.thresholds, weeklyThresholds)
        XCTAssertEqual(resolved.alertLevel, .warning)
    }

    func testCriticalSessionWinsOverWarningWeekly() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 10, weekly: 22)))

        XCTAssertEqual(resolved.window.remainingPercent, 10)
        XCTAssertEqual(resolved.kind, .session)
        XCTAssertEqual(resolved.thresholds, sessionThresholds)
        XCTAssertEqual(resolved.alertLevel, .error)
    }

    func testQuietSnapshotFallsBackToSession() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 90, weekly: 88)))

        XCTAssertEqual(resolved.window.remainingPercent, 90)
        XCTAssertEqual(resolved.kind, .session)
        XCTAssertEqual(resolved.alertLevel, .normal)
    }

    func testEmptyThresholdsFallBackUnlessWeeklyExhausted() throws {
        let quiet = try XCTUnwrap(resolve(
            snapshot(session: 76, weekly: 22),
            sessionThresholds: [],
            weeklyThresholds: []
        ))
        XCTAssertEqual(quiet.kind, .session)
        XCTAssertEqual(quiet.window.remainingPercent, 76)

        let exhausted = try XCTUnwrap(resolve(
            snapshot(session: 76, weekly: 0),
            sessionThresholds: [],
            weeklyThresholds: []
        ))
        XCTAssertEqual(exhausted.kind, .weekly)
        XCTAssertEqual(exhausted.window.remainingPercent, 0)
        XCTAssertTrue(exhausted.isExhausted)
        XCTAssertEqual(exhausted.alertLevel, .error)
    }

    func testMonthlyCriticalWinsOverQuietWindows() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 90, weekly: 85, monthly: 15)))

        XCTAssertEqual(resolved.window.remainingPercent, 15)
        XCTAssertEqual(resolved.kind, .monthly)
        XCTAssertEqual(resolved.title, "30-day")
        XCTAssertEqual(resolved.thresholds, weeklyThresholds)
        XCTAssertEqual(resolved.alertLevel, .error)
    }

    func testModelCriticalWinsOverQuietWindows() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 90, weekly: 85, models: [60, 12])))

        XCTAssertEqual(resolved.window.remainingPercent, 12)
        XCTAssertEqual(resolved.kind, .model)
        XCTAssertEqual(resolved.title, "Model1")
        XCTAssertEqual(resolved.thresholds, weeklyThresholds)
    }

    func testSnapshotWithoutWindowsResolvesToNil() {
        XCTAssertNil(resolve(UsageQuotaSnapshot.unavailable(
            providerID: .codex,
            statusNote: nil
        )))
    }

    func testTiesHonorDeclaredOrder() throws {
        let sessionFirst = try XCTUnwrap(resolve(snapshot(session: 20, weekly: 20)))
        XCTAssertEqual(sessionFirst.kind, .session)

        let modelsFirst = try XCTUnwrap(resolve(snapshot(models: [40, 40])))
        XCTAssertEqual(modelsFirst.title, "Model0")
        XCTAssertEqual(modelsFirst.window.remainingPercent, 40)
    }

    func testFallbackOrderIsSessionWeeklyMonthlyModel() throws {
        let weeklyFallback = try XCTUnwrap(resolve(snapshot(weekly: 88)))
        XCTAssertEqual(weeklyFallback.kind, .weekly)

        let monthlyFallback = try XCTUnwrap(resolve(snapshot(monthly: 70)))
        XCTAssertEqual(monthlyFallback.kind, .monthly)
        XCTAssertEqual(monthlyFallback.title, "30-day")

        let modelFallback = try XCTUnwrap(resolve(snapshot(models: [70, 60])))
        XCTAssertEqual(modelFallback.title, "Model1")
        XCTAssertEqual(modelFallback.window.remainingPercent, 60)

        let modelTieFallback = try XCTUnwrap(resolve(snapshot(models: [70, 70])))
        XCTAssertEqual(modelTieFallback.title, "Model0")

        let monthlyOverModel = try XCTUnwrap(resolve(snapshot(monthly: 70, models: [60])))
        XCTAssertEqual(monthlyOverModel.kind, .monthly)
        XCTAssertEqual(monthlyOverModel.title, "30-day")
        XCTAssertEqual(monthlyOverModel.window.remainingPercent, 70)
    }

    func testSessionThresholdsDoNotLeakIntoWeekly() throws {
        let resolved = try XCTUnwrap(resolve(
            snapshot(session: 20, weekly: 40),
            sessionThresholds: [90],
            weeklyThresholds: [50]
        ))

        XCTAssertEqual(resolved.kind, .weekly)
        XCTAssertEqual(resolved.window.remainingPercent, 40)
    }

    func testWeeklyThresholdsDoNotLeakIntoSession() throws {
        let resolved = try XCTUnwrap(resolve(
            snapshot(session: 40, weekly: 10),
            sessionThresholds: [50],
            weeklyThresholds: [95]
        ))

        XCTAssertEqual(resolved.kind, .session)
        XCTAssertEqual(resolved.window.remainingPercent, 40)
    }

    func testExhaustedWeeklyBeatsWorseSession() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 5, weekly: 0)))

        XCTAssertEqual(resolved.kind, .weekly)
        XCTAssertTrue(resolved.isExhausted)
    }

    func testChoiceIgnoresValueStyle() throws {
        let remaining = try XCTUnwrap(resolve(snapshot(session: 76, weekly: 22)))

        XCTAssertEqual(remaining.window.remainingPercent, 22)
        XCTAssertEqual(remaining.kind, .weekly)
        XCTAssertEqual(
            UsageQuotaFormatting.compactDisplayValueText(
                remainingPercent: remaining.window.remainingPercent,
                kind: remaining.kind,
                showUsed: false
            ),
            "22%"
        )
        XCTAssertEqual(
            UsageQuotaFormatting.compactDisplayValueText(
                remainingPercent: remaining.window.remainingPercent,
                kind: remaining.kind,
                showUsed: true
            ),
            "78%"
        )
    }

    private func reading(
        for resolved: UsageQuotaSummaryResolution,
        showUsed: Bool,
        showPace: Bool = true
    ) -> UsageQuotaPace.Reading {
        UsageQuotaPace.reading(
            for: resolved.window,
            showUsed: showUsed,
            thresholds: [],
            workdaysPerWeek: 5,
            showPace: showPace,
            now: now
        )
    }

    func testDescribeNamesProviderWindowValueAndPace() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 76, weekly: 22)))
        let description = UsageQuotaSummaryResolution.describe(
            displayName: "Claude Code",
            resolution: resolved,
            reading: reading(for: resolved, showUsed: false),
            isStale: false
        )

        XCTAssertEqual(
            description,
            "Claude Code, Weekly, 22% left, 42% in deficit, Runs out in 16m"
        )
        XCTAssertFalse(description.contains("Session"))
        XCTAssertFalse(description.contains("76%"))
    }

    func testDescribeKeepsUsedDirectionWithSameWindow() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 76, weekly: 22)))
        let description = UsageQuotaSummaryResolution.describe(
            displayName: "Claude Code",
            resolution: resolved,
            reading: reading(for: resolved, showUsed: true),
            isStale: false
        )

        XCTAssertTrue(description.hasPrefix("Claude Code, Weekly, 78% used"))
        XCTAssertFalse(description.contains("Session"))
    }

    func testDescribeMarksStaleAsOutdated() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 41, isStale: true)))
        let description = UsageQuotaSummaryResolution.describe(
            displayName: "Cursor",
            resolution: resolved,
            reading: reading(for: resolved, showUsed: false),
            isStale: true
        )

        XCTAssertTrue(description.hasSuffix(", Outdated"))
        XCTAssertFalse(description.contains("stale"))
    }

    func testDescribeExhaustedKeepsExplicitReading() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 76, weekly: 0)))
        let description = UsageQuotaSummaryResolution.describe(
            displayName: "Antigravity",
            resolution: resolved,
            reading: reading(for: resolved, showUsed: false),
            isStale: false
        )

        XCTAssertEqual(description, "Antigravity, Weekly, quota exhausted")
    }

    func testDescribeOmitsPaceWithoutAValidMarker() throws {
        let resolved = try XCTUnwrap(resolve(snapshot(session: 76, weekly: 22)))
        let reading = reading(for: resolved, showUsed: false, showPace: false)
        XCTAssertNil(reading.paceLeftText)
        XCTAssertNil(reading.paceRightText)

        let description = UsageQuotaSummaryResolution.describe(
            displayName: "Claude Code",
            resolution: resolved,
            reading: reading,
            isStale: false
        )

        XCTAssertEqual(description, "Claude Code, Weekly, 22% left")
    }

    private func resolveSelected(
        _ snapshot: UsageQuotaSnapshot,
        _ metrics: [UsageQuotaPresentationPreferences.Metric]
    ) -> [UsageQuotaWindowKind] {
        UsageQuotaSummaryResolution.resolveSelected(
            snapshot: snapshot,
            metrics: metrics,
            sessionThresholds: sessionThresholds,
            weeklyThresholds: weeklyThresholds
        ).map(\.kind)
    }

    func testSelectedMetricsKeepUserOrderOverCriticalWindow() {
        XCTAssertEqual(resolveSelected(snapshot(session: 90, weekly: 10), [.session]), [.session])
        XCTAssertEqual(resolveSelected(snapshot(session: 90, weekly: 10), [.weekly, .session]), [.weekly, .session])
    }

    func testSelectedMetricsSkipMissingWindowsAndCredits() {
        XCTAssertEqual(resolveSelected(snapshot(session: 90), [.credits, .weekly, .session]), [.session])
    }

    func testUnresolvedSelectionFallsBackToCriticalWindow() {
        XCTAssertEqual(resolveSelected(snapshot(models: [60, 12]), [.session, .weekly]), [.model])
        XCTAssertEqual(resolveSelected(snapshot(session: 90, weekly: 10), []), [.weekly])
    }

    func testExhaustedWeeklyReplacesSelection() {
        XCTAssertEqual(resolveSelected(snapshot(session: 90, weekly: 0), [.session]), [.weekly])
    }
}
