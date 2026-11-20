import Foundation

struct UsageQuotaSummaryResolution: Equatable, Sendable {
    let window: UsageWindow
    let kind: UsageQuotaWindowKind
    let thresholds: [Int]
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

    private static func alertedMinimum(candidates: [Self]) -> Self? {
        candidates.filter { $0.alertLevel != .normal }
            .min(by: { $0.window.remainingPercent < $1.window.remainingPercent })
    }

    private static func quietFallback(candidates: [Self]) -> Self? {
        if let first = candidates.first(where: { $0.kind != .model }) {
            return first
        }
        return candidates.min(by: { $0.window.remainingPercent < $1.window.remainingPercent })
    }

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
