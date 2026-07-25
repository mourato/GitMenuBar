import Foundation

enum UsageProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case cursor

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .cursor:
            return "Cursor"
        }
    }
}

struct UsageWindow: Codable, Equatable, Sendable {
    let remainingPercent: Int
    let resetAt: Date?
    let label: String
    /// Provider-reported limit duration when known (from `limit_window_seconds` / `window_minutes`).
    let durationSeconds: Int?

    init(remainingPercent: Int, resetAt: Date?, label: String, durationSeconds: Int? = nil) {
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetAt = resetAt
        self.label = label
        self.durationSeconds = durationSeconds.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Compact interval chip shown in the footer strip (e.g. `5h`, `7d`, `Plan`).
    var intervalChip: String {
        if let durationSeconds {
            return UsageQuotaFormatting.intervalChip(durationSeconds: durationSeconds)
        }
        return label
    }
}

struct UsageQuotaSnapshot: Codable, Equatable, Identifiable, Sendable {
    let providerID: UsageProviderID
    let displayName: String
    let sessionWindow: UsageWindow?
    let weeklyWindow: UsageWindow?
    let creditValueText: String?
    /// Codex limit-reset credits still available (from `wham/rate-limit-reset-credits`).
    let resetCreditsAvailable: Int?
    let isAvailable: Bool
    let isStale: Bool
    let statusNote: String?
    let fetchedAt: Date

    var id: UsageProviderID {
        providerID
    }

    /// Prefer the tighter active window for the strip hero metric when both exist.
    var primaryDisplayWindow: UsageWindow? {
        switch (sessionWindow, weeklyWindow) {
        case let (session?, weekly?):
            return session.remainingPercent <= weekly.remainingPercent ? session : weekly
        case let (session?, nil):
            return session
        case let (nil, weekly?):
            return weekly
        case (nil, nil):
            return nil
        }
    }

    init(
        providerID: UsageProviderID,
        displayName: String,
        sessionWindow: UsageWindow?,
        weeklyWindow: UsageWindow?,
        creditValueText: String? = nil,
        resetCreditsAvailable: Int? = nil,
        isAvailable: Bool,
        isStale: Bool = false,
        statusNote: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.sessionWindow = sessionWindow
        self.weeklyWindow = weeklyWindow
        self.creditValueText = creditValueText
        self.resetCreditsAvailable = resetCreditsAvailable.flatMap { $0 > 0 ? $0 : nil }
        self.isAvailable = isAvailable
        self.isStale = isStale
        self.statusNote = statusNote
        self.fetchedAt = fetchedAt
    }

    static func unavailable(
        providerID: UsageProviderID,
        statusNote: String?
    ) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: providerID,
            displayName: providerID.displayName,
            sessionWindow: nil,
            weeklyWindow: nil,
            isAvailable: false,
            statusNote: statusNote
        )
    }

    func markingStale(note: String?) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: providerID,
            displayName: displayName,
            sessionWindow: sessionWindow,
            weeklyWindow: weeklyWindow,
            creditValueText: creditValueText,
            resetCreditsAvailable: resetCreditsAvailable,
            isAvailable: isAvailable,
            isStale: true,
            statusNote: note ?? statusNote,
            fetchedAt: fetchedAt
        )
    }

    func withResetCreditsAvailable(_ count: Int?) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: providerID,
            displayName: displayName,
            sessionWindow: sessionWindow,
            weeklyWindow: weeklyWindow,
            creditValueText: creditValueText,
            resetCreditsAvailable: count,
            isAvailable: isAvailable,
            isStale: isStale,
            statusNote: statusNote,
            fetchedAt: fetchedAt
        )
    }
}

enum UsageQuotaFormatting {
    static func remainingPercent(fromUsed used: Double) -> Int {
        max(0, min(100, Int((100 - used).rounded())))
    }

    static func intervalChip(durationSeconds: Int) -> String {
        let hours = Double(durationSeconds) / 3600
        if hours < 1 {
            let minutes = max(1, Int((Double(durationSeconds) / 60).rounded()))
            return "\(minutes)m"
        }
        if hours < 36 {
            let roundedHours = max(1, Int(hours.rounded()))
            return "\(roundedHours)h"
        }
        let days = hours / 24
        let roundedDays = max(1, Int(days.rounded()))
        return "\(roundedDays)d"
    }

    static func intervalLabel(durationSeconds: Int?, fallback: String) -> String {
        guard let durationSeconds, durationSeconds > 0 else { return fallback }
        return intervalChip(durationSeconds: durationSeconds)
    }

    static func resetCountdown(until resetAt: Date?, now: Date = Date()) -> String {
        guard let resetAt, resetAt > now else { return "—" }

        let interval = Int(resetAt.timeIntervalSince(now))
        let days = interval / 86400
        let hours = (interval % 86400) / 3600
        let minutes = (interval % 3600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }

    static func trafficLightColor(for remainingPercent: Int) -> UsageQuotaTrafficLight {
        if remainingPercent >= 40 {
            return .green
        }
        if remainingPercent >= 15 {
            return .amber
        }
        return .red
    }
}

enum UsageQuotaTrafficLight: Sendable {
    case green
    case amber
    case red
}
