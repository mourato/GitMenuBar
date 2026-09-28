import Foundation

struct ClaudeCodeOAuthCredentials: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let rawData: Data

    init(accessToken: String, refreshToken: String?, expiresAt: Date?, rawData: Data = Data()) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.rawData = rawData
    }
}

enum ClaudeCodeUsageParsing {
    static func credentials(fromCredentials data: Data) -> ClaudeCodeOAuthCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty
        else {
            return nil
        }

        let refreshToken = (oauth["refreshToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAt = doubleValue(oauth["expiresAt"]).map {
            Date(timeIntervalSince1970: $0 / 1000)
        }
        return ClaudeCodeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken.flatMap { $0.isEmpty ? nil : $0 },
            expiresAt: expiresAt,
            rawData: data
        )
    }

    static func accessToken(fromCredentials data: Data) -> String? {
        credentials(fromCredentials: data)?.accessToken
    }

    static func snapshot(fromUsageAPI data: Data, now: Date = Date()) -> UsageQuotaSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let session = usageWindow(
            from: root["five_hour"] as? [String: Any],
            label: "5h",
            durationSeconds: 5 * 3600
        )
        let weekly = usageWindow(
            from: root["seven_day"] as? [String: Any],
            label: "7d",
            durationSeconds: 7 * 86400
        )
        let modelWindows = modelWindows(from: root)
        guard session != nil || weekly != nil || !modelWindows.isEmpty else { return nil }

        return UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: UsageProviderID.claudeCode.displayName,
            sessionWindow: session,
            weeklyWindow: weekly,
            modelWindows: modelWindows,
            isAvailable: true,
            statusNote: "Claude Code OAuth usage API",
            fetchedAt: now
        )
    }

    static func snapshot(fromJSONL text: String, now: Date = Date()) -> UsageQuotaSnapshot? {
        var windows: [String: UsageWindow] = [:]

        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["type"] as? String == "rate_limit_event",
                  let info = root["rate_limit_info"] as? [String: Any],
                  let rateLimitType = info["rateLimitType"] as? String,
                  let utilization = doubleValue(info["utilization"])
            else { continue }

            let fraction = utilization <= 1 ? utilization : utilization / 100
            let durationSeconds: Int? = if rateLimitType.localizedStandardContains("five_hour") {
                5 * 3600
            } else if rateLimitType.localizedStandardContains("seven_day") {
                7 * 86400
            } else {
                nil
            }
            let window = UsageWindow(
                remainingPercent: UsageQuotaFormatting.remainingPercent(fromUsed: fraction * 100),
                resetAt: resetDate(from: info["resetsAt"]),
                label: durationSeconds.map(UsageQuotaFormatting.intervalChip) ?? rateLimitType,
                durationSeconds: durationSeconds
            )
            if windows[rateLimitType] == nil {
                windows[rateLimitType] = window
            }
        }

        let session = windows.first { $0.key.localizedStandardContains("five_hour") }?.value
        let weekly = windows.first { $0.key.localizedStandardContains("seven_day") }?.value
        guard session != nil || weekly != nil else { return nil }

        return UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: UsageProviderID.claudeCode.displayName,
            sessionWindow: session,
            weeklyWindow: weekly,
            isAvailable: true,
            statusNote: "Claude Code local rate limit events",
            fetchedAt: now
        )
    }

    private static func usageWindow(
        from value: [String: Any]?,
        label: String,
        durationSeconds: Int
    ) -> UsageWindow? {
        guard let value,
              let utilization = doubleValue(value["utilization"] ?? value["used_percentage"]),
              utilization.isFinite
        else {
            return nil
        }

        let usedPercent = utilization <= 1 ? utilization * 100 : utilization
        return UsageWindow(
            remainingPercent: UsageQuotaFormatting.remainingPercent(fromUsed: usedPercent),
            resetAt: resetDate(from: value["resets_at"] ?? value["resetsAt"]),
            label: label,
            durationSeconds: durationSeconds
        )
    }

    private static func modelWindows(from root: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        var seenModels = Set<String>()

        func append(_ window: UsageWindow, modelKey: String) {
            guard seenModels.insert(modelKey.lowercased()).inserted else { return }
            windows.append(window)
        }

        for definition in [("seven_day_sonnet", "Sonnet"), ("seven_day_opus", "Opus")] {
            guard let window = usageWindow(
                from: root[definition.0] as? [String: Any],
                label: definition.1,
                durationSeconds: 7 * 86400
            ) else {
                continue
            }
            append(window, modelKey: definition.1)
        }

        guard let limits = root["limits"] as? [[String: Any]] else { return windows }
        for limit in limits {
            guard limit["group"] as? String == "weekly",
                  limit["kind"] as? String == "weekly_scoped",
                  let scope = limit["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let modelName = model["display_name"] as? String,
                  !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  modelName.caseInsensitiveCompare("All models") != .orderedSame,
                  let percent = doubleValue(limit["percent"]),
                  percent.isFinite,
                  let window = modelWindow(
                      usedPercent: percent,
                      label: "\(modelName) only",
                      resetAt: limit["resets_at"]
                  )
            else {
                continue
            }
            append(window, modelKey: modelName)
        }
        return windows
    }

    private static func modelWindow(
        usedPercent: Double,
        label: String,
        resetAt: Any?
    ) -> UsageWindow? {
        guard usedPercent.isFinite else { return nil }
        return UsageWindow(
            remainingPercent: UsageQuotaFormatting.remainingPercent(fromUsed: usedPercent),
            resetAt: resetDate(from: resetAt),
            label: label,
            durationSeconds: 7 * 86400
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func resetDate(from value: Any?) -> Date? {
        if let seconds = doubleValue(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }
}
