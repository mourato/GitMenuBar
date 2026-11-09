import Foundation

/// Parsing for the OpenCode Go public usage API.
///
/// Ported from CodexBar's `OpenCodeGoUsageFetcher.parseAPIUsage` (MIT, steipete):
/// `GET https://opencode.ai/zen/go/v1/usage` with `Authorization: Bearer <key>`
/// answers `{"usage": {"rolling": {"percent": 0...100, "resetsAt": ISO8601},
/// "weekly": {...}, "monthly": {...}}}`. Percents already use 0...100 units.
enum OpenCodeGoUsageParsing {
    static func snapshot(fromAPIData data: Data, now: Date = Date()) -> UsageQuotaSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any],
              let rolling = usage["rolling"] as? [String: Any]
        else {
            return nil
        }
        return snapshot(
            rolling: rolling,
            weekly: usage["weekly"] as? [String: Any],
            monthly: usage["monthly"] as? [String: Any],
            now: now
        )
    }

    static func snapshot(
        rolling: [String: Any],
        weekly: [String: Any]?,
        monthly: [String: Any]?,
        now: Date = Date()
    ) -> UsageQuotaSnapshot? {
        guard let session = window(rolling, label: "5h", durationSeconds: 5 * 3600, now: now) else {
            return nil
        }
        let weeklyWindow = weekly.flatMap { window($0, label: "7d", durationSeconds: 7 * 86400, now: now) }
        // Weekly key present but unparsable invalidates the payload like CodexBar's buildSnapshot.
        if weekly != nil, weeklyWindow == nil {
            return nil
        }
        let monthlyWindow = monthly.flatMap { window($0, label: "30d", durationSeconds: 30 * 86400, now: now) }
        return UsageQuotaSnapshot(
            providerID: .opencodeGo,
            displayName: UsageProviderID.opencodeGo.displayName,
            sessionWindow: session,
            weeklyWindow: weeklyWindow,
            tertiaryMonthlyWindow: monthlyWindow,
            isAvailable: true,
            statusNote: "opencode go usage api"
        )
    }

    private static func window(
        _ dict: [String: Any],
        label: String,
        durationSeconds: Int,
        now: Date
    ) -> UsageWindow? {
        guard let used = percent(dict) else { return nil }
        return UsageWindow(
            remainingPercent: UsageQuotaFormatting.remainingPercent(fromUsed: used),
            resetAt: resetAt(dict, now: now),
            label: label,
            durationSeconds: durationSeconds
        )
    }

    private static func percent(_ dict: [String: Any]) -> Double? {
        for key in ["percent", "usagePercent", "usedPercent", "used"] {
            if let value = doubleValue(dict[key]) {
                return value
            }
        }
        if let used = doubleValue(dict["used"] ?? dict["usage"] ?? dict["consumed"]),
           let limit = doubleValue(dict["limit"] ?? dict["total"] ?? dict["quota"] ?? dict["max"]),
           limit > 0
        {
            return used / limit * 100
        }
        return nil
    }

    private static func resetAt(_ dict: [String: Any], now: Date) -> Date? {
        for key in ["resetsAt", "resetAt", "reset_at", "resets_at"] {
            if let date = dateValue(dict[key]), date > now {
                return date
            }
        }
        if let seconds = intValue(dict["resetInSec"] ?? dict["reset_in_sec"] ?? dict["resetInSeconds"]),
           seconds >= 0
        {
            return now.addingTimeInterval(TimeInterval(seconds))
        }
        return nil
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        switch raw {
        case let value as Double:
            value.isFinite ? value : nil
        case let value as Float:
            value.isFinite ? Double(value) : nil
        case let value as Int:
            Double(value)
        case let value as Int64:
            Double(value)
        case let value as NSNumber:
            value.doubleValue.isFinite ? value.doubleValue : nil
        case let value as String:
            Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            nil
        }
    }

    private static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            value
        case let value as Int64:
            Int(value)
        case let value as Double where value.isFinite:
            Int(value)
        case let value as NSNumber:
            value.intValue
        case let value as String:
            Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            nil
        }
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        if let number = raw as? NSNumber {
            let seconds = number.doubleValue > 1_000_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
            guard seconds.isFinite, seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let seconds = Double(text), seconds > 0 {
            let resolved = seconds > 1_000_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: resolved)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
