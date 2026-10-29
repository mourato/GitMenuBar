import Foundation
import SwiftUI

enum UsageProviderID: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case claudeCode
    case codex
    case cursor
    case openrouter
    case gemini
    case antigravity

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        case .cursor:
            "Cursor"
        case .openrouter:
            "OpenRouter"
        case .gemini:
            "Gemini"
        case .antigravity:
            "Antigravity"
        }
    }

    /// Brand tint for the provider logo in quota cards; the menu-bar strip stays monochrome.
    var brandColor: Color {
        switch self {
        case .claudeCode:
            Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex:
            Color(red: 0.45, green: 0.47, blue: 0.98)
        case .gemini:
            Color(red: 0.31, green: 0.53, blue: 0.97)
        case .antigravity:
            Color(red: 0.26, green: 0.52, blue: 0.96)
        case .cursor, .openrouter:
            Color(nsColor: .labelColor)
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

/// One redeemable Codex limit reset, with the date it stops being redeemable.
struct UsageQuotaResetCredit: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let expiresAt: Date
}

struct UsageQuotaSnapshot: Codable, Equatable, Identifiable, Sendable {
    let providerID: UsageProviderID
    let displayName: String
    let sessionWindow: UsageWindow?
    let weeklyWindow: UsageWindow?
    let modelWindows: [UsageWindow]
    let creditValueText: String?
    /// Codex limit-reset credits still available (from `wham/rate-limit-reset-credits`).
    let resetCreditsAvailable: Int?
    /// Redeemable reset credits with expiry, soonest first. Empty when the provider does not report them.
    let resetCredits: [UsageQuotaResetCredit]
    /// Provider-reported plan name when known (e.g. Codex `chatgpt_plan_type`, Cursor `membershipType`).
    let planText: String?
    let isAvailable: Bool
    let isStale: Bool
    let statusNote: String?
    let fetchedAt: Date

    var id: UsageProviderID {
        providerID
    }

    /// The shortest available window drives the strip hero metric; weekly is the fallback.
    var primaryDisplayWindow: UsageWindow? {
        sessionWindow ?? weeklyWindow
    }

    init(
        providerID: UsageProviderID,
        displayName: String,
        sessionWindow: UsageWindow?,
        weeklyWindow: UsageWindow?,
        modelWindows: [UsageWindow] = [],
        creditValueText: String? = nil,
        resetCreditsAvailable: Int? = nil,
        resetCredits: [UsageQuotaResetCredit] = [],
        planText: String? = nil,
        isAvailable: Bool,
        isStale: Bool = false,
        statusNote: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.sessionWindow = sessionWindow
        self.weeklyWindow = weeklyWindow
        self.modelWindows = modelWindows
        self.creditValueText = creditValueText
        self.resetCreditsAvailable = resetCreditsAvailable.flatMap { $0 > 0 ? $0 : nil }
        self.resetCredits = resetCredits
        self.planText = planText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        self.isAvailable = isAvailable
        self.isStale = isStale
        self.statusNote = statusNote
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case displayName
        case sessionWindow
        case weeklyWindow
        case modelWindows
        case creditValueText
        case resetCreditsAvailable
        case resetCredits
        case planText
        case isAvailable
        case isStale
        case statusNote
        case fetchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(UsageProviderID.self, forKey: .providerID)
        displayName = try container.decode(String.self, forKey: .displayName)
        sessionWindow = try container.decodeIfPresent(UsageWindow.self, forKey: .sessionWindow)
        weeklyWindow = try container.decodeIfPresent(UsageWindow.self, forKey: .weeklyWindow)
        modelWindows = try container.decodeIfPresent([UsageWindow].self, forKey: .modelWindows) ?? []
        creditValueText = try container.decodeIfPresent(String.self, forKey: .creditValueText)
        resetCreditsAvailable = try container.decodeIfPresent(Int.self, forKey: .resetCreditsAvailable)
        resetCredits = try container.decodeIfPresent([UsageQuotaResetCredit].self, forKey: .resetCredits) ?? []
        planText = try container.decodeIfPresent(String.self, forKey: .planText)
        isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        isStale = try container.decode(Bool.self, forKey: .isStale)
        statusNote = try container.decodeIfPresent(String.self, forKey: .statusNote)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
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
            modelWindows: modelWindows,
            creditValueText: creditValueText,
            resetCreditsAvailable: resetCreditsAvailable,
            resetCredits: resetCredits,
            planText: planText,
            isAvailable: isAvailable,
            isStale: true,
            statusNote: note ?? statusNote,
            fetchedAt: fetchedAt
        )
    }

    func withResetCredits(_ inventory: CodexResetCreditInventory) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: providerID,
            displayName: displayName,
            sessionWindow: sessionWindow,
            weeklyWindow: weeklyWindow,
            modelWindows: modelWindows,
            creditValueText: creditValueText,
            resetCreditsAvailable: inventory.availableCount,
            resetCredits: inventory.credits,
            planText: planText,
            isAvailable: isAvailable,
            isStale: isStale,
            statusNote: statusNote,
            fetchedAt: fetchedAt
        )
    }

    func withPlanText(_ plan: String?) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: providerID,
            displayName: displayName,
            sessionWindow: sessionWindow,
            weeklyWindow: weeklyWindow,
            modelWindows: modelWindows,
            creditValueText: creditValueText,
            resetCreditsAvailable: resetCreditsAvailable,
            resetCredits: resetCredits,
            planText: plan,
            isAvailable: isAvailable,
            isStale: isStale,
            statusNote: statusNote,
            fetchedAt: fetchedAt
        )
    }
}

/// Plan display names derived from provider payloads (no new sources).
enum UsageQuotaPlanNaming {
    /// Capitalized raw value (`pro` → `Pro`); nil/blank stays nil.
    static func display(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// Cursor `membershipType` mapping (mirrors CodexBar's plan labels).
    static func cursor(_ membershipType: String?) -> String? {
        guard let type = membershipType?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty else {
            return nil
        }
        return cursorPlans[type.lowercased()] ?? display(type)
    }

    private static let cursorPlans = [
        "enterprise": "Enterprise",
        "express": "Start",
        "free": "Free",
        "free_trial": "Pro Trial",
        "hobby": "Hobby",
        "pro": "Pro",
        "pro_student": "Pro",
        "pro_plus": "Pro+",
        "team": "Team",
        "ultra": "Ultra"
    ]
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

    /// Locale-aware time-only string for the next quota reset (e.g. `18:27` / `6:27 PM`).
    /// Returns an em dash when `resetAt` is nil or not in the future, matching `resetCountdown`.
    static func resetClockTime(
        until resetAt: Date?,
        locale: Locale = .current,
        now: Date = Date()
    ) -> String {
        guard let resetAt, resetAt > now else { return "—" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: resetAt)
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

    /// Locale-aware short label for when a snapshot was last successfully read
    /// (e.g. `14:32` / `2:32 PM`). Used by stale-state explanations.
    static func fetchedAtLabel(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
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

    /// Alert level against configured used-percent thresholds: normal until the first
    /// threshold is reached, warning past the first, error past the second or later.
    static func alertLevel(remainingPercent: Int, thresholds: [Int]) -> UsageQuotaAlertLevel {
        let usedPercent = 100 - remainingPercent
        let crossed = thresholds.filter { usedPercent >= $0 }.count
        if crossed >= 2 {
            return .error
        }
        if crossed == 1 {
            return .warning
        }
        return .normal
    }
}

enum UsageQuotaTrafficLight: Sendable {
    case green
    case amber
    case red
}

enum UsageQuotaAlertLevel: Sendable {
    case normal
    case warning
    case error
}
