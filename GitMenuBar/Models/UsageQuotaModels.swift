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

    init(remainingPercent: Int, resetAt: Date?, label: String) {
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetAt = resetAt
        self.label = label
    }
}

struct UsageQuotaSnapshot: Codable, Equatable, Identifiable, Sendable {
    let providerID: UsageProviderID
    let displayName: String
    let sessionWindow: UsageWindow?
    let weeklyWindow: UsageWindow?
    let creditValueText: String?
    let isAvailable: Bool
    let isStale: Bool
    let statusNote: String?
    let fetchedAt: Date

    var id: UsageProviderID {
        providerID
    }

    init(
        providerID: UsageProviderID,
        displayName: String,
        sessionWindow: UsageWindow?,
        weeklyWindow: UsageWindow?,
        creditValueText: String? = nil,
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
            isAvailable: isAvailable,
            isStale: true,
            statusNote: note ?? statusNote,
            fetchedAt: fetchedAt
        )
    }
}

enum UsageQuotaFormatting {
    static func remainingPercent(fromUsed used: Double) -> Int {
        max(0, min(100, Int((100 - used).rounded())))
    }

    static func resetCountdown(until resetAt: Date?, now: Date = Date()) -> String {
        guard let resetAt, resetAt > now else { return "—" }

        let interval = Int(resetAt.timeIntervalSince(now))
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60

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
