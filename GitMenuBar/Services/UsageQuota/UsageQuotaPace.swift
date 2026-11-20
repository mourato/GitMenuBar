import Foundation

enum UsageQuotaPace {
    static let weeklyWindowSeconds = 7 * 86400

    static let minimumExpectedUsedPercent = 3.0

    static let defaultWarningThresholds = [50, 80]

    enum Stage: String, Equatable, Sendable {
        case onTrack
        case ahead
        case behind
    }

    struct Pace: Equatable, Sendable {
        let expectedUsedPercent: Double
        let actualUsedPercent: Double
        let stage: Stage
        let paceOnTop: Bool
        let willLastToReset: Bool
        let etaSeconds: TimeInterval?

        var deltaPercent: Double {
            actualUsedPercent - expectedUsedPercent
        }
    }

    struct Reading: Equatable, Sendable {
        let fillPercent: Double
        let percentText: String
        let resetCountdownText: String?
        let resetText: String?
        let detailText: String?
        let paceLeftText: String?
        let paceRightText: String?
        let pacePercent: Double?
        let paceDeficit: Bool
        let warningMarkerPercents: [Double]
        let workdayMarkerPercents: [Double]
    }

    static func pace(for window: UsageWindow, now: Date = Date()) -> Pace? {
        guard window.remainingPercent > 0,
              let durationSeconds = window.durationSeconds,
              durationSeconds > 0,
              let resetAt = window.resetAt
        else {
            return nil
        }
        let duration = TimeInterval(durationSeconds)
        let timeUntilReset = resetAt.timeIntervalSince(now)
        guard timeUntilReset > 0, timeUntilReset <= duration else {
            return nil
        }
        let elapsed = duration - timeUntilReset
        let expected = elapsed / duration * 100
        guard expected >= minimumExpectedUsedPercent else {
            return nil
        }
        let actual = Double(100 - window.remainingPercent)
        let delta = actual - expected
        let stage: Stage = if abs(delta) <= 2 {
            .onTrack
        } else if delta > 0 {
            .ahead
        } else {
            .behind
        }

        var willLastToReset = false
        var etaSeconds: TimeInterval?
        if actual <= 0 {
            willLastToReset = true
        } else if elapsed > 0 {
            let rate = actual / elapsed
            if rate > 0 {
                let candidate = (100 - actual) / rate
                if candidate >= timeUntilReset {
                    willLastToReset = true
                } else {
                    etaSeconds = candidate
                }
            }
        }
        return Pace(
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            stage: stage,
            paceOnTop: actual <= expected,
            willLastToReset: willLastToReset,
            etaSeconds: etaSeconds
        )
    }

    static func reading(
        for window: UsageWindow,
        showUsed: Bool,
        thresholds: [Int],
        workdaysPerWeek: Int,
        showPace: Bool,
        now: Date = Date()
    ) -> Reading {
        let used = 100 - window.remainingPercent
        let fillPercent = showUsed ? Double(used) : Double(window.remainingPercent)
        let percentText = showUsed ? "\(used)% used" : "\(window.remainingPercent)% left"
        let resetCountdownText: String? = if let resetAt = window.resetAt, resetAt > now {
            UsageQuotaFormatting.resetCountdown(until: resetAt, now: now)
        } else {
            nil
        }
        let resetText = resetCountdownText.map { "Resets in \($0)" }
        let clockTime = UsageQuotaFormatting.resetClockTime(until: window.resetAt, now: now)
        let detailText: String? = clockTime == "—" ? nil : "Resets at \(clockTime)"

        var paceLeftText: String?
        var paceRightText: String?
        var pacePercent: Double?
        var paceDeficit = false
        if showPace, let pace = pace(for: window, now: now) {
            paceLeftText = leftLabel(for: pace)
            paceRightText = rightLabel(for: pace, now: now)
            if pace.stage != .onTrack {
                pacePercent = paceMarkerPercent(
                    expectedUsedPercent: pace.expectedUsedPercent,
                    showUsed: showUsed
                )
            }
            paceDeficit = !pace.paceOnTop
        }
        return Reading(
            fillPercent: fillPercent,
            percentText: percentText,
            resetCountdownText: resetCountdownText,
            resetText: resetText,
            detailText: detailText,
            paceLeftText: paceLeftText,
            paceRightText: paceRightText,
            pacePercent: pacePercent,
            paceDeficit: paceDeficit,
            warningMarkerPercents: warningMarkerPercents(thresholds: thresholds, showUsed: showUsed),
            workdayMarkerPercents: workdayMarkerPercents(
                workdaysPerWeek: workdaysPerWeek,
                durationSeconds: window.durationSeconds
            )
        )
    }

    static func warningMarkerPercents(thresholds: [Int], showUsed: Bool) -> [Double] {
        thresholds
            .map { showUsed ? Double($0) : 100 - Double($0) }
            .filter { $0 > 0 && $0 < 100 }
            .reduce(into: [Double]()) { result, value in
                if !result.contains(where: { abs($0 - value) < 0.001 }) {
                    result.append(value)
                }
            }
            .sorted()
    }

    static func workdayMarkerPercents(workdaysPerWeek: Int, durationSeconds: Int?) -> [Double] {
        guard durationSeconds == weeklyWindowSeconds, (2 ... 7).contains(workdaysPerWeek) else {
            return []
        }
        return (1 ..< workdaysPerWeek).map { Double($0) * 100 / Double(workdaysPerWeek) }
    }

    static func paceMarkerPercent(expectedUsedPercent: Double, showUsed: Bool) -> Double {
        showUsed ? expectedUsedPercent : 100 - expectedUsedPercent
    }

    static func rowTitle(isSessionWindow: Bool, window: UsageWindow) -> String {
        if isSessionWindow {
            guard let seconds = window.durationSeconds else { return window.label }
            return seconds < 86400 && seconds % 3600 == 0 ? "\(seconds / 3600)-hour" : "Session"
        }
        return window.durationSeconds == nil ? window.label : "Weekly"
    }

    static func leftLabel(for pace: Pace) -> String {
        let magnitude = Int(abs(pace.deltaPercent).rounded())
        switch pace.stage {
        case .onTrack:
            return "On pace"
        case .ahead:
            return "\(magnitude)% in deficit"
        case .behind:
            return "\(magnitude)% in reserve"
        }
    }

    static func rightLabel(for pace: Pace, now: Date = Date()) -> String? {
        if pace.willLastToReset {
            return "Lasts until reset"
        }
        guard let etaSeconds = pace.etaSeconds else {
            return nil
        }
        if etaSeconds <= 0 {
            return "Runs out now"
        }
        let countdown = UsageQuotaFormatting.resetCountdown(
            until: now.addingTimeInterval(etaSeconds),
            now: now
        )
        guard countdown != "—" else {
            return nil
        }
        return "Runs out in \(countdown)"
    }

    static func sanitizedThresholds(_ raw: [Int]) -> [Int] {
        Set(raw.map { min(99, max(1, $0)) }).sorted()
    }

    static func parseThresholds(_ text: String) -> [Int]? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        let values = text
            .components(separatedBy: CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines))
            .compactMap { Int($0) }
        guard !values.isEmpty else {
            return nil
        }
        return sanitizedThresholds(values)
    }

    static func canonicalThresholdsText(_ thresholds: [Int]) -> String {
        thresholds.map(String.init).joined(separator: ", ")
    }
}
