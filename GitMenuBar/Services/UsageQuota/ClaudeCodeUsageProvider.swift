import Foundation

struct ClaudeCodeUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .claudeCode

    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    // swiftlint:disable:next async_without_await
    func fetchSnapshot() async -> UsageQuotaSnapshot {
        let projectsDirectory = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .unavailable(providerID: id, statusNote: "Claude Code sessions not found")
        }

        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { modificationDate(for: $0) > modificationDate(for: $1) }

        for file in files.prefix(12) {
            guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { continue }
            let tail = data.count > 256_000 ? data.suffix(256_000) : data[...]
            guard let text = String(data: Data(tail), encoding: .utf8) else { continue }
            if let snapshot = ClaudeCodeUsageParsing.snapshot(fromJSONL: text) {
                return snapshot
            }
        }

        return .unavailable(providerID: id, statusNote: "Claude Code rate limits not reported yet")
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

enum ClaudeCodeUsageParsing {
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
            let durationSeconds: Int? = if rateLimitType.localizedCaseInsensitiveContains("five_hour") {
                5 * 3600
            } else if rateLimitType.localizedCaseInsensitiveContains("seven_day") {
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

        let session = windows.first { $0.key.localizedCaseInsensitiveContains("five_hour") }?.value
        let weekly = windows.first { $0.key.localizedCaseInsensitiveContains("seven_day") }?.value
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
