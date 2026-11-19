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

    // MARK: - Mandatory acceptance cases

    func testCriticalWeeklyWinsOverQuietSession() throws {
        // Session 76% left is 24% used (below 50): quiet.
        // Weekly 22% left is 78% used (past 50): warning.
        let resolved = try XCTUnwrap(resolve(snapshot(session: 76, weekly: 22)))

        XCTAssertEqual(resolved.window.remainingPercent, 22)
        XCTAssertEqual(resolved.kind, .weekly)
        XCTAssertEqual(resolved.title, "Weekly")
        XCTAssertEqual(resolved.thresholds, weeklyThresholds)
        XCTAssertEqual(resolved.alertLevel, .warning)
    }

    func testCriticalSessionWinsOverWarningWeekly() throws {
        // Session 10% left is 90% used: error. Weekly 22% left: warning.
        // The least remaining quota wins.
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

    // MARK: - Ties and order

    func testTiesHonorDeclaredOrder() throws {
        // Both windows error (80% used); Session comes first.
        let sessionFirst = try XCTUnwrap(resolve(snapshot(session: 20, weekly: 20)))
        XCTAssertEqual(sessionFirst.kind, .session)

        // Both models warn (60% used); the provided order wins.
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

        // Quiet model ties keep the provided order.
        let modelTieFallback = try XCTUnwrap(resolve(snapshot(models: [70, 70])))
        XCTAssertEqual(modelTieFallback.title, "Model0")

        // Monthly keeps its own fallback slot ahead of the tightest model.
        let monthlyOverModel = try XCTUnwrap(resolve(snapshot(monthly: 70, models: [60])))
        XCTAssertEqual(monthlyOverModel.kind, .monthly)
        XCTAssertEqual(monthlyOverModel.title, "30-day")
        XCTAssertEqual(monthlyOverModel.window.remainingPercent, 70)
    }

    // MARK: - Per-window thresholds

    func testSessionThresholdsDoNotLeakIntoWeekly() throws {
        // Session 20% left is 80% used: quiet under session [90], but would
        // warn under the weekly thresholds. Weekly 40% left is 60% used:
        // warning under weekly [50]. Weekly must win despite more remaining.
        let resolved = try XCTUnwrap(resolve(
            snapshot(session: 20, weekly: 40),
            sessionThresholds: [90],
            weeklyThresholds: [50]
        ))

        XCTAssertEqual(resolved.kind, .weekly)
        XCTAssertEqual(resolved.window.remainingPercent, 40)
    }

    func testWeeklyThresholdsDoNotLeakIntoSession() throws {
        // Weekly 10% left is 90% used: quiet under weekly [95], but would
        // error under the session thresholds. Session 40% left is 60% used:
        // warning under session [50]. Session must win despite more remaining.
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

    // MARK: - Used/Remaining invariance

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

    // MARK: - Shared tooltip and VoiceOver string

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

        // 22% left with 36% expected used against 78% actual: 42% in deficit.
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

    // MARK: - Selected metrics

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
