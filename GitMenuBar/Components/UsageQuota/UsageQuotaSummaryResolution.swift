import Foundation

/// Window resolution for the sidebar footer summary.
///
/// The footer shows the same metrics the user selected for the menu bar
/// (`resolveSelected`). One resolution drives the meter, the percent, the
/// tooltip, and VoiceOver, so the footer never names one window while drawing
/// another.
struct UsageQuotaSummaryResolution: Equatable, Sendable {
    let window: UsageWindow
    let kind: UsageQuotaWindowKind
    /// Thresholds belonging to the resolved window: the session thresholds for
    /// Session, the weekly thresholds for every other window.
    let thresholds: [Int]
    /// Window name for the tooltip and VoiceOver, matching the detail card row.
    let title: String

    var isExhausted: Bool {
        UsageQuotaFormatting.isWeeklyExhausted(
            remainingPercent: window.remainingPercent,
            kind: kind
        )
    }

    var alertLevel: UsageQuotaAlertLevel {
        if isExhausted {
            return .error
        }
        return UsageQuotaFormatting.alertLevel(
            remainingPercent: window.remainingPercent,
            thresholds: thresholds
        )
    }

    /// The user's selected metrics, in their order, for the footer. An
    /// exhausted weekly window replaces them so its alert stays visible.
    /// Credits have no window to draw and are skipped; when no selected
    /// metric resolves, the footer falls back to the critical window so the
    /// provider stays visible.
    static func resolveSelected(
        snapshot: UsageQuotaSnapshot,
        metrics: [UsageQuotaPresentationPreferences.Metric],
        sessionThresholds: [Int],
        weeklyThresholds: [Int]
    ) -> [Self] {
        if let exhausted = exhaustedWeeklyResolution(snapshot: snapshot, weeklyThresholds: weeklyThresholds) {
            return [exhausted]
        }
        let candidates = orderedCandidates(
            snapshot: snapshot,
            sessionThresholds: sessionThresholds,
            weeklyThresholds: weeklyThresholds
        )
        let selected = metrics.compactMap { metric -> Self? in
            let kind: UsageQuotaWindowKind
            switch metric {
            case .session: kind = .session
            case .weekly: kind = .weekly
            case .monthly: kind = .monthly
            case .credits: return nil
            }
            return candidates.first { $0.kind == kind }
        }
        if !selected.isEmpty {
            return selected
        }
        return resolve(
            snapshot: snapshot,
            sessionThresholds: sessionThresholds,
            weeklyThresholds: weeklyThresholds
        ).map { [$0] } ?? []
    }

    /// Session, Weekly, Monthly, then the provided model order. An exhausted
    /// weekly window keeps its special state ahead of every alert; otherwise
    /// the alerting window with the least remaining quota wins, and a quiet
    /// snapshot falls back to the first declared window. The Remaining/Used
    /// style never changes the choice.
    static func resolve(
        snapshot: UsageQuotaSnapshot,
        sessionThresholds: [Int],
        weeklyThresholds: [Int]
    ) -> Self? {
        if let exhausted = exhaustedWeeklyResolution(snapshot: snapshot, weeklyThresholds: weeklyThresholds) {
            return exhausted
        }
        let candidates = orderedCandidates(
            snapshot: snapshot,
            sessionThresholds: sessionThresholds,
            weeklyThresholds: weeklyThresholds
        )
        guard !candidates.isEmpty else { return nil }
        if let critical = alertedMinimum(candidates: candidates) {
            return critical
        }
        return quietFallback(candidates: candidates)
    }

    private static func exhaustedWeeklyResolution(
        snapshot: UsageQuotaSnapshot,
        weeklyThresholds: [Int]
    ) -> Self? {
        guard let weekly = snapshot.weeklyWindow, weekly.remainingPercent == 0 else { return nil }
        return Self(
            window: weekly,
            kind: .weekly,
            thresholds: weeklyThresholds,
            title: UsageQuotaPace.rowTitle(isSessionWindow: false, window: weekly)
        )
    }

    private static func orderedCandidates(
        snapshot: UsageQuotaSnapshot,
        sessionThresholds: [Int],
        weeklyThresholds: [Int]
    ) -> [Self] {
        var candidates: [Self] = []
        if let session = snapshot.sessionWindow {
            candidates.append(Self(
                window: session,
                kind: .session,
                thresholds: sessionThresholds,
                title: UsageQuotaPace.rowTitle(isSessionWindow: true, window: session)
            ))
        }
        if let weekly = snapshot.weeklyWindow {
            candidates.append(Self(
                window: weekly,
                kind: .weekly,
                thresholds: weeklyThresholds,
                title: UsageQuotaPace.rowTitle(isSessionWindow: false, window: weekly)
            ))
        }
        if let monthly = snapshot.tertiaryMonthlyWindow {
            candidates.append(Self(
                window: monthly,
                kind: .monthly,
                thresholds: weeklyThresholds,
                title: monthly.label
            ))
        }
        for model in snapshot.modelWindows {
            candidates.append(Self(
                window: model,
                kind: .model,
                thresholds: weeklyThresholds,
                title: model.label
            ))
        }
        return candidates
    }

    /// `min(by:)` keeps the first minimum, so ties honor the declared order
    /// and models keep their provided order.
    private static func alertedMinimum(candidates: [Self]) -> Self? {
        candidates.filter { $0.alertLevel != .normal }
            .min(by: { $0.window.remainingPercent < $1.window.remainingPercent })
    }

    /// Quiet fallback: Session → Weekly → Monthly → the tightest model.
    private static func quietFallback(candidates: [Self]) -> Self? {
        if let first = candidates.first(where: { $0.kind != .model }) {
            return first
        }
        return candidates.min(by: { $0.window.remainingPercent < $1.window.remainingPercent })
    }

    /// Provider, window, remaining or used percent, pace state when the reading
    /// carries one, and the stale marker. The tooltip and VoiceOver share it.
    static func describe(
        displayName: String,
        resolution: Self,
        reading: UsageQuotaPace.Reading,
        isStale: Bool
    ) -> String {
        var parts = [displayName, resolution.title]
        if resolution.isExhausted {
            parts.append("quota exhausted")
        } else {
            parts.append(reading.percentText)
            if let paceLeft = reading.paceLeftText {
                parts.append(paceLeft)
            }
            if let paceRight = reading.paceRightText {
                parts.append(paceRight)
            }
        }
        if isStale {
            parts.append("Outdated")
        }
        return parts.joined(separator: ", ")
    }
}
