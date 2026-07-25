import Foundation

/// Parsing helpers for Cursor's unofficial dashboard usage API.
enum CursorUsageParsing {
    static func sessionCookieValue(accessToken: String) -> String? {
        guard let userID = userID(fromJWT: accessToken) else {
            return nil
        }
        return "\(userID)%3A%3A\(accessToken)"
    }

    static func userID(fromJWT token: String) -> String? {
        guard let payload = decodeJWTPayload(token),
              let subject = payload["sub"] as? String,
              !subject.isEmpty else {
            return nil
        }

        if let separatorIndex = subject.lastIndex(of: "|") {
            return String(subject[subject.index(after: separatorIndex)...])
        }
        return subject
    }

    static func snapshot(fromUsageSummary data: Data) -> UsageQuotaSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return snapshot(fromUsageSummary: root)
    }

    static func snapshot(fromUsageSummary root: [String: Any]) -> UsageQuotaSnapshot? {
        let billingCycleEnd = parseISO8601Date(root["billingCycleEnd"])
        let isUnlimited = root["isUnlimited"] as? Bool ?? false

        guard let individualUsage = root["individualUsage"] as? [String: Any],
              let plan = individualUsage["plan"] as? [String: Any] else {
            return nil
        }

        let remainingPercent = remainingPercent(fromPlan: plan, isUnlimited: isUnlimited)
        guard let remainingPercent else {
            return nil
        }

        let creditValueText = creditValueText(fromPlan: plan, isUnlimited: isUnlimited)
        let cycleStart = parseISO8601Date(root["billingCycleStart"])
        let durationSeconds: Int? = {
            guard let cycleStart, let billingCycleEnd else { return nil }
            let seconds = Int(billingCycleEnd.timeIntervalSince(cycleStart))
            return seconds > 0 ? seconds : nil
        }()

        return UsageQuotaSnapshot(
            providerID: .cursor,
            displayName: UsageProviderID.cursor.displayName,
            sessionWindow: UsageWindow(
                remainingPercent: remainingPercent,
                resetAt: billingCycleEnd,
                label: UsageQuotaFormatting.intervalLabel(durationSeconds: durationSeconds, fallback: "Plan"),
                durationSeconds: durationSeconds
            ),
            weeklyWindow: nil,
            creditValueText: creditValueText,
            isAvailable: true,
            statusNote: "cursor usage-summary api"
        )
    }

    static func remainingPercent(fromPlan plan: [String: Any], isUnlimited: Bool) -> Int? {
        if isUnlimited || plan["enabled"] as? Bool == false {
            return 100
        }

        if let totalPercentUsed = doubleValue(plan["totalPercentUsed"]) {
            return UsageQuotaFormatting.remainingPercent(fromUsed: totalPercentUsed)
        }

        guard let used = doubleValue(plan["used"]),
              let limit = doubleValue(plan["limit"]),
              limit > 0 else {
            return nil
        }

        let usedPercent = (used / limit) * 100
        return UsageQuotaFormatting.remainingPercent(fromUsed: usedPercent)
    }

    static func creditValueText(fromPlan plan: [String: Any], isUnlimited: Bool) -> String? {
        if isUnlimited {
            return "Unlimited"
        }

        if let remaining = doubleValue(plan["remaining"]), remaining > 0 {
            return String(format: "$%.2f left", remaining / 100)
        }

        return nil
    }

    static func parseISO8601Date(_ raw: Any?) -> Date? {
        guard let text = raw as? String, !text.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: padding)
        }

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double {
            return value
        }
        if let value = raw as? Int {
            return Double(value)
        }
        if let value = raw as? NSNumber {
            return value.doubleValue
        }
        if let value = raw as? String {
            return Double(value)
        }
        return nil
    }
}
