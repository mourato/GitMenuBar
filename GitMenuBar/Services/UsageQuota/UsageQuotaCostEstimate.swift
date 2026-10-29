import Foundation
import Synchronization

/// Current-month API-equivalent spend estimate for subscription token usage.
/// `nil` amounts mean "seen but unpriced"; providers without any monthly
/// records are omitted so the card only appears when there is usage to show.
struct UsageQuotaCostEstimate: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        /// Icon source (`.claudeCode` for Anthropic, `.codex` for OpenAI).
        let providerID: UsageProviderID
        let title: String
        let monthLabel: String
        let amountUSD: Double?
    }

    let rows: [Row]
}

enum UsageQuotaCostScanner {
    typealias PricingSource = UsageQuotaModelsDevStore.PricingSource

    private enum Constants {
        /// ponytail: per-file totals cached in memory (keyed by path, mtime, size, monthStart); cold start and first scan after relaunch still read every listed file. Persist the cache if cold start shows up in profiles.
        static let maxFilesPerRoot = 600
        static let maxFileBytes = 96 * 1024 * 1024
    }

    /// Per-file scan results reused while the file's mtime, size, month and
    /// pricing source are unchanged.
    private struct CachedFileTotal: Sendable {
        let modified: Date
        let size: Int
        let monthStart: Date
        let pricingToken: String
        let total: CostTotal
    }

    private static let fileCache = Mutex<[String: CachedFileTotal]>([:])

    static func estimate(
        homeDirectory: URL,
        now: Date = Date(),
        pricing: PricingSource = .bundled
    ) -> UsageQuotaCostEstimate {
        guard !Task.isCancelled else { return UsageQuotaCostEstimate(rows: []) }
        let monthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        ) ?? now
        let monthLabel = Self.monthLabel(for: now)

        let codexRoots = [
            homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        ]
        let claudeRoot = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)

        let codexFiles = codexRoots.flatMap { jsonlFiles(under: $0, monthStart: monthStart) }
        guard !Task.isCancelled else { return UsageQuotaCostEstimate(rows: []) }
        let claudeFiles = jsonlFiles(under: claudeRoot, monthStart: monthStart)
        guard !Task.isCancelled else { return UsageQuotaCostEstimate(rows: []) }

        var cache: [String: CachedFileTotal] = [:]
        let codex = summedTotal(
            of: codexFiles,
            monthStart: monthStart,
            pricingToken: pricing.token,
            cache: &cache
        ) { file, month in
            scanCodexFile(file, monthStart: month, catalog: pricing.catalog)
        }
        let claude = summedTotal(
            of: claudeFiles,
            monthStart: monthStart,
            pricingToken: pricing.token,
            cache: &cache
        ) { file, month in
            scanClaudeFile(file, monthStart: month, catalog: pricing.catalog)
        }
        // Replacing the whole cache drops entries for files no longer listed.
        fileCache.withLock { $0 = cache }

        var rows: [UsageQuotaCostEstimate.Row] = []
        if codex.hasRecords {
            rows.append(UsageQuotaCostEstimate.Row(
                providerID: .codex,
                title: "OpenAI API",
                monthLabel: monthLabel,
                amountUSD: codex.hasPricedRecords ? codex.totalUSD : nil
            ))
        }
        if claude.hasRecords {
            rows.append(UsageQuotaCostEstimate.Row(
                providerID: .claudeCode,
                title: "Anthropic API",
                monthLabel: monthLabel,
                amountUSD: claude.hasPricedRecords ? claude.totalUSD : nil
            ))
        }
        return UsageQuotaCostEstimate(rows: rows)
    }

    static func monthLabel(for date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    static func amountText(_ amountUSD: Double?) -> String {
        guard let amountUSD else { return "—" }
        return String(format: "$%.2f", amountUSD)
    }

    // MARK: - Codex

    private struct CodexTurnUsage: Sendable {
        var input = 0
        var cached = 0
        var cacheWrite = 0
        var output = 0
    }

    private static func scanCodexFile(
        _ file: URL,
        monthStart: Date,
        catalog: ModelsDevCatalog?
    ) -> CostTotal {
        var total = CostTotal()
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return total }
        let records = parseCodexRecords(text)
        let turnModels = codexTurnModels(records)
        let fileModel = codexFileModel(records)
        // `token_usage_record` and `token_count` describe the same turns; prefer the former.
        let priced = codexPricedUsages(records, monthStart: monthStart, turnModels: turnModels)
        guard !priced.isEmpty else { return total }
        total.hasRecords = true
        for (turnModel, usage) in priced {
            guard let cost = UsageQuotaAPIPricing.codexCostUSD(
                model: turnModel ?? fileModel ?? "unknown",
                inputTokens: usage.input,
                cachedInputTokens: usage.cached,
                cacheWriteInputTokens: usage.cacheWrite,
                outputTokens: usage.output,
                catalog: catalog
            ) else { continue }
            total.totalUSD += cost
            total.hasPricedRecords = true
        }
        return total
    }

    private static func parseCodexRecords(_ text: String) -> [[String: Any]] {
        var records: [[String: Any]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.contains("turn_id") || line.contains("token") || line.contains("model"),
                  let data = String(line).data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            records.append(record)
        }
        return records
    }

    private static func codexTurnModels(_ records: [[String: Any]]) -> [String: String] {
        var turnModels: [String: String] = [:]
        for record in records {
            guard record["type"] as? String == "turn_context",
                  let payload = record["payload"] as? [String: Any],
                  let turnID = payload["turn_id"] as? String,
                  let model = payload["model"] as? String
            else { continue }
            turnModels[turnID] = model
        }
        return turnModels
    }

    private static func codexFileModel(_ records: [[String: Any]]) -> String? {
        for record in records {
            guard record["type"] as? String == "event_msg",
                  let payload = record["payload"] as? [String: Any],
                  payload["type"] as? String == "thread_settings_applied",
                  let settings = payload["thread_settings"] as? [String: Any],
                  let model = settings["model"] as? String
            else { continue }
            return model
        }
        for record in records {
            guard record["type"] as? String == "session_meta",
                  let payload = record["payload"] as? [String: Any],
                  let meta = payload["base_instructions"] as? [String: Any],
                  let provenance = meta["provenance"] as? [String: Any],
                  let model = provenance["model"] as? String
            else { continue }
            return model
        }
        return nil
    }

    private static func codexPricedUsages(
        _ records: [[String: Any]],
        monthStart: Date,
        turnModels: [String: String]
    ) -> [(String?, CodexTurnUsage)] {
        var turns: [String: CodexTurnUsage] = [:]
        var ordinalUsages: [Int: CodexTurnUsage] = [:]
        for record in records {
            guard let timestamp = isoDate(record["timestamp"]), timestamp >= monthStart else { continue }
            let payload = record["payload"] as? [String: Any]
            if record["type"] as? String == "token_usage_record",
               let payload,
               let turnID = payload["turn_id"] as? String,
               turns[turnID] == nil,
               let usage = payload["turn_token_usage"] as? [String: Any] ?? payload["usage"] as? [String: Any]
            {
                turns[turnID] = codexUsage(from: usage)
            } else if record["type"] as? String == "event_msg",
                      payload?["type"] as? String == "token_count",
                      let info = payload?["info"] as? [String: Any],
                      let usage = info["last_token_usage"] as? [String: Any],
                      let ordinal = record["ordinal"] as? Int,
                      ordinalUsages[ordinal] == nil
            {
                ordinalUsages[ordinal] = codexUsage(from: usage)
            }
        }
        if !turns.isEmpty {
            return turns.map { (turnModels[$0.key], $0.value) }
        }
        return ordinalUsages.values.map { (nil as String?, $0) }
    }

    private static func codexUsage(from usage: [String: Any]) -> CodexTurnUsage {
        CodexTurnUsage(
            input: intValue(usage["input_tokens"]),
            cached: intValue(usage["cached_input_tokens"]),
            cacheWrite: intValue(usage["cache_write_input_tokens"]),
            output: intValue(usage["output_tokens"])
        )
    }

    // MARK: - Claude

    private static func scanClaudeFile(
        _ file: URL,
        monthStart: Date,
        catalog: ModelsDevCatalog?
    ) -> CostTotal {
        var total = CostTotal()
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return total }
        var seenRequestIDs = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.contains("\"usage\""),
                  let data = String(line).data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = record["message"] as? [String: Any],
                  message["role"] as? String == "assistant",
                  let usage = message["usage"] as? [String: Any],
                  let timestamp = isoDate(record["timestamp"]), timestamp >= monthStart
            else { continue }
            let dedupKey = (record["requestId"] as? String) ?? (record["uuid"] as? String) ?? ""
            guard !dedupKey.isEmpty, seenRequestIDs.insert(dedupKey).inserted else { continue }
            total.hasRecords = true
            let model = (message["model"] as? String)
                ?? (record["requestedModel"] as? String)
                ?? "unknown"
            let cacheCreation = usage["cache_creation"] as? [String: Any]
            guard let cost = UsageQuotaAPIPricing.claudeCostUSD(
                model: model,
                inputTokens: intValue(usage["input_tokens"]),
                cacheReadInputTokens: intValue(usage["cache_read_input_tokens"]),
                cacheCreationInputTokens: intValue(usage["cache_creation_input_tokens"]),
                cacheCreationInputTokens1h: intValue(cacheCreation?["ephemeral_1h_input_tokens"]),
                outputTokens: intValue(usage["output_tokens"]),
                catalog: catalog
            ) else { continue }
            total.totalUSD += cost
            total.hasPricedRecords = true
        }
        return total
    }

    // MARK: - Helpers

    /// One file's contribution; files are summed into a provider total.
    private struct CostTotal: Sendable {
        var totalUSD = 0.0
        var hasRecords = false
        var hasPricedRecords = false
    }

    private struct ScannedFile {
        let url: URL
        let modified: Date
        let size: Int
    }

    /// Sums per-file totals, reusing cached values for files whose mtime, size,
    /// month and pricing source are unchanged. Fills `cache` with every file
    /// visited so the caller can replace the stored cache.
    private static func summedTotal(
        of files: [ScannedFile],
        monthStart: Date,
        pricingToken: String,
        cache: inout [String: CachedFileTotal],
        scan: (URL, Date) -> CostTotal
    ) -> CostTotal {
        let previous = fileCache.withLock { $0 }
        var total = CostTotal()
        for file in files {
            guard !Task.isCancelled else { break }
            let key = file.url.path
            let fileTotal = previous[key].flatMap { hit in
                hit.modified == file.modified && hit.size == file.size
                    && hit.monthStart == monthStart && hit.pricingToken == pricingToken
                    ? hit.total
                    : nil
            } ?? scan(file.url, monthStart)
            cache[key] = CachedFileTotal(
                modified: file.modified,
                size: file.size,
                monthStart: monthStart,
                pricingToken: pricingToken,
                total: fileTotal
            )
            total.totalUSD += fileTotal.totalUSD
            total.hasRecords = total.hasRecords || fileTotal.hasRecords
            total.hasPricedRecords = total.hasPricedRecords || fileTotal.hasPricedRecords
        }
        return total
    }

    /// Files modified before `monthStart` cannot hold this month's records, so they are skipped unread.
    private static func jsonlFiles(under root: URL, monthStart: Date) -> [ScannedFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [ScannedFile] = []
        while let raw = enumerator.nextObject() {
            guard !Task.isCancelled else { break }
            guard let url = raw as? URL, url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  date >= monthStart,
                  (values.fileSize ?? 0) <= Constants.maxFileBytes
            else { continue }
            files.append(ScannedFile(url: url, modified: date, size: values.fileSize ?? 0))
        }
        return Array(files
            .sorted { $0.modified > $1.modified }
            .prefix(Constants.maxFilesPerRoot))
    }

    private static func isoFormatter(withFractional: Bool) -> ISO8601DateFormatter {
        let key = withFractional ? "UsageQuotaCostFractional" : "UsageQuotaCostPlain"
        if let cached = Thread.current.threadDictionary[key] as? ISO8601DateFormatter {
            return cached
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }

    static func isoDate(_ raw: Any?) -> Date? {
        guard let text = raw as? String, !text.isEmpty else { return nil }
        return isoFormatter(withFractional: true).date(from: text)
            ?? isoFormatter(withFractional: false).date(from: text)
    }

    static func intValue(_ raw: Any?) -> Int {
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
        return 0
    }
}
