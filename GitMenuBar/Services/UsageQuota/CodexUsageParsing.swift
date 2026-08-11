import Foundation

/// Parsing helpers adapted from Mimir (MIT, Eray Endes) — Codex usage ladder only.
enum CodexUsageParsing {
    struct APIWindow {
        let usedPercent: Double?
        let resetAt: Date?
        let durationSeconds: Int?
    }

    static func remainingPercent(fromUsed used: Double) -> Int {
        UsageQuotaFormatting.remainingPercent(fromUsed: used)
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

    static func codexAPIWindow(_ raw: Any?) -> APIWindow {
        guard let object = raw as? [String: Any] else {
            return APIWindow(usedPercent: nil, resetAt: nil, durationSeconds: nil)
        }

        let used = doubleValue(object["used_percent"])
        let reset = doubleValue(object["reset_at"]).map { Date(timeIntervalSince1970: $0) }
        let duration = intValue(object["limit_window_seconds"])
            ?? intValue(object["window_minutes"]).map { $0 * 60 }
        return APIWindow(usedPercent: used, resetAt: reset, durationSeconds: duration)
    }

    static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? Double {
            return Int(value.rounded())
        }
        if let value = raw as? NSNumber {
            return value.intValue
        }
        if let value = raw as? String, let parsed = Int(value) {
            return parsed
        }
        return nil
    }

    /// Decode CodexBar-compatible reset-credit inventory payloads.
    static func resetCreditsAvailable(from data: Data, now: Date = Date()) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let count = intValue(root["available_count"]) ?? intValue(root["availableCount"]) {
            return max(0, count)
        }
        guard let credits = root["credits"] as? [[String: Any]] else {
            return nil
        }
        let available = credits.filter { credit in
            if let expiresRaw = credit["expires_at"] ?? credit["expiresAt"] {
                if let text = expiresRaw as? String,
                   let expiresAt = parseISO8601Date(text),
                   expiresAt <= now
                {
                    return false
                }
                if let epoch = doubleValue(expiresRaw),
                   Date(timeIntervalSince1970: epoch) <= now
                {
                    return false
                }
            }
            return true
        }
        return available.count
    }

    private static func parseISO8601Date(_ text: String) -> Date? {
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
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return payload
    }

    static func jwtExpiry(_ token: String) -> Date? {
        guard let payload = decodeJWTPayload(token),
              let expiry = doubleValue(payload["exp"])
        else {
            return nil
        }
        return Date(timeIntervalSince1970: expiry)
    }

    static func codexAccountID(from auth: [String: Any]) -> String? {
        if let accountID = auth["account_id"] as? String, !accountID.isEmpty {
            return accountID
        }
        if let tokens = auth["tokens"] as? [String: Any] {
            if let accountID = tokens["account_id"] as? String, !accountID.isEmpty {
                return accountID
            }
            if let idToken = tokens["id_token"] as? String,
               let accountID = codexAccountID(fromJWT: idToken)
            {
                return accountID
            }
        }
        if let idToken = auth["id_token"] as? String,
           let accountID = codexAccountID(fromJWT: idToken)
        {
            return accountID
        }
        return nil
    }

    static func codexAccountID(fromJWT token: String) -> String? {
        guard let payload = decodeJWTPayload(token),
              let auth = payload["https://api.openai.com/auth"] as? [String: Any],
              let accountID = auth["chatgpt_account_id"] as? String,
              !accountID.isEmpty
        else {
            return nil
        }
        return accountID
    }

    static func codexAccessToken(in auth: [String: Any]) -> String? {
        if let token = auth["access_token"] as? String, !token.isEmpty {
            return token
        }
        if let tokens = auth["tokens"] as? [String: Any],
           let token = tokens["access_token"] as? String,
           !token.isEmpty
        {
            return token
        }
        return nil
    }

    static func codexRefreshToken(in auth: [String: Any]) -> String? {
        if let token = auth["refresh_token"] as? String, !token.isEmpty {
            return token
        }
        if let tokens = auth["tokens"] as? [String: Any],
           let token = tokens["refresh_token"] as? String,
           !token.isEmpty
        {
            return token
        }
        return nil
    }

    static func creditValueText(from raw: Any?) -> String? {
        guard let credits = raw as? [String: Any] else { return nil }
        if credits["unlimited"] as? Bool == true {
            return "Unlimited"
        }
        guard credits["has_credits"] as? Bool == true else { return nil }
        let amount = (credits["balance"] as? String).flatMap(Double.init) ?? doubleValue(credits["balance"]) ?? 0
        guard amount > 0 else { return nil }
        let text = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(amount)
        return "\(text) credits"
    }

    static func snapshot(fromUsageAPI root: [String: Any]) -> UsageQuotaSnapshot? {
        guard let rateLimit = root["rate_limit"] as? [String: Any] else { return nil }

        let session = codexAPIWindow(rateLimit["primary_window"])
        let weekly = codexAPIWindow(rateLimit["secondary_window"])

        return UsageQuotaSnapshot(
            providerID: .codex,
            displayName: UsageProviderID.codex.displayName,
            sessionWindow: session.usedPercent.map {
                UsageWindow(
                    remainingPercent: remainingPercent(fromUsed: $0),
                    resetAt: session.resetAt,
                    label: UsageQuotaFormatting.intervalLabel(
                        durationSeconds: session.durationSeconds,
                        fallback: "Session"
                    ),
                    durationSeconds: session.durationSeconds
                )
            },
            weeklyWindow: weekly.usedPercent.map {
                UsageWindow(
                    remainingPercent: remainingPercent(fromUsed: $0),
                    resetAt: weekly.resetAt,
                    label: UsageQuotaFormatting.intervalLabel(
                        durationSeconds: weekly.durationSeconds,
                        fallback: "Weekly"
                    ),
                    durationSeconds: weekly.durationSeconds
                )
            },
            creditValueText: creditValueText(from: root["credits"]),
            isAvailable: true,
            statusNote: "chatgpt usage api"
        )
    }

    static func summarizeCodexWindow(_ window: CodexRateWindow?, now: Date) -> CodexWindowSummary? {
        guard let window else { return nil }
        let used = window.usedPercent ?? 0
        guard let resetEpoch = window.resetsAt else {
            return CodexWindowSummary(usedPercent: used, resetAt: nil)
        }

        var reset = Date(timeIntervalSince1970: TimeInterval(resetEpoch))
        if reset <= now, let minutes = window.windowMinutes, minutes > 0 {
            while reset <= now {
                reset = reset.addingTimeInterval(TimeInterval(minutes * 60))
            }
            return CodexWindowSummary(usedPercent: 0, resetAt: reset)
        }
        if reset <= now {
            return CodexWindowSummary(usedPercent: 0, resetAt: nil)
        }
        return CodexWindowSummary(usedPercent: used, resetAt: reset)
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func snapshot(fromSessionsJSONL text: String, now: Date = Date()) -> UsageQuotaSnapshot? {
        let lines = text.split(separator: "\n").reversed()
        var sessionRemaining: Int?
        var weeklyRemaining: Int?
        var sessionReset: Date?
        var weeklyReset: Date?
        var sessionDuration: Int?
        var weeklyDuration: Int?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let record = try? JSONDecoder().decode(CodexSessionRecord.self, from: data),
                  record.type == "event_msg",
                  record.payload?.type == "token_count",
                  let rateLimits = record.payload?.rateLimits else { continue }

            if let primary = rateLimits.primary {
                if sessionDuration == nil, let minutes = primary.windowMinutes {
                    sessionDuration = minutes * 60
                }
                if let summary = summarizeCodexWindow(primary, now: now) {
                    if sessionRemaining == nil {
                        sessionRemaining = remainingPercent(fromUsed: summary.usedPercent)
                    }
                    if sessionReset == nil {
                        sessionReset = summary.resetAt
                    }
                }
            }

            if let secondary = rateLimits.secondary {
                if weeklyDuration == nil, let minutes = secondary.windowMinutes {
                    weeklyDuration = minutes * 60
                }
                if let summary = summarizeCodexWindow(secondary, now: now) {
                    if weeklyRemaining == nil {
                        weeklyRemaining = remainingPercent(fromUsed: summary.usedPercent)
                    }
                    if weeklyReset == nil {
                        weeklyReset = summary.resetAt
                    }
                }
            }

            if sessionRemaining != nil, weeklyRemaining != nil, sessionReset != nil, weeklyReset != nil {
                break
            }
        }

        guard sessionRemaining != nil || weeklyRemaining != nil else { return nil }

        let statusNote = sessionReset == nil
            ? "local .codex sessions (reset time not found in file)"
            : "local .codex sessions"

        return UsageQuotaSnapshot(
            providerID: .codex,
            displayName: UsageProviderID.codex.displayName,
            sessionWindow: sessionRemaining.map {
                UsageWindow(
                    remainingPercent: $0,
                    resetAt: sessionReset,
                    label: UsageQuotaFormatting.intervalLabel(durationSeconds: sessionDuration, fallback: "Session"),
                    durationSeconds: sessionDuration
                )
            },
            weeklyWindow: weeklyRemaining.map {
                UsageWindow(
                    remainingPercent: $0,
                    resetAt: weeklyReset,
                    label: UsageQuotaFormatting.intervalLabel(durationSeconds: weeklyDuration, fallback: "Weekly"),
                    durationSeconds: weeklyDuration
                )
            },
            isAvailable: true,
            statusNote: statusNote
        )
    }

    static func latestJSONLFile(in directory: URL, fileManager: FileManager = .default) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return nil
        }

        var latest: (URL, Date)?
        while let raw = enumerator.nextObject() {
            guard let url = raw as? URL, url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else { continue }
            if let currentLatest = latest, currentLatest.1 > date {
                continue
            }
            latest = (url, date)
        }
        return latest?.0
    }

    static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

struct CodexWindowSummary {
    let usedPercent: Double
    let resetAt: Date?
}

struct CodexSessionRecord: Decodable {
    let type: String?
    let payload: CodexPayload?
}

struct CodexPayload: Decodable {
    let type: String?
    let rateLimits: CodexRateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

struct CodexRateLimits: Decodable {
    let primary: CodexRateWindow?
    let secondary: CodexRateWindow?
}

struct CodexRateWindow: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
