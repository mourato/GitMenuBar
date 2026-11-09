import Foundation
import SQLite3

/// Device-local OpenCode Go cost estimate from `~/.local/share/opencode/opencode.db`.
///
/// Ported from CodexBar's `OpenCodeGoLocalUsageReader` (MIT, steipete) with one
/// deliberate simplification: CodexBar materializes every usage row and keeps a
/// 4 MiB cache; Fase 1 aggregates inside SQLite (`SUM`/`MIN` per window) so a
/// large local history never enters Swift memory. SQL filters, the
/// `opencode-go` provider predicate, legacy `message`/`part` + v2
/// `session_message` coverage, migrated-message dedup, and the fixed
/// $12/$30/$60 denominators are unchanged. Like CodexBar, these denominators
/// are fixed estimates, not detected subscription tiers, and local history
/// covers only this device.
enum OpenCodeGoLocalUsage {
    private static let fiveHours: TimeInterval = 5 * 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60
    private static let limits = (session: 12.0, weekly: 30.0, monthly: 60.0)

    static func snapshot(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()
    ) -> UsageQuotaSnapshot? {
        guard let databaseURL = databaseURL(homeDirectory: homeDirectory, environment: environment),
              FileManager.default.fileExists(atPath: databaseURL.path),
              let bounds = monthAnchorBounds(databaseURL: databaseURL, now: now)
        else {
            return nil
        }
        return aggregate(databaseURL: databaseURL, now: now, anchorMs: bounds.anchorMs, month: bounds.month)
    }

    // MARK: - Paths (mirrors CodexBar's XDG_DATA_HOME / OPENCODE_DB lookup)

    private static func databaseURL(homeDirectory: URL, environment: [String: String]) -> URL? {
        let dataHome = environment["XDG_DATA_HOME"].flatMap { path in
            path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true) : nil
        } ?? homeDirectory.appendingPathComponent(".local/share", isDirectory: true)
        let directory = dataHome.appendingPathComponent("opencode", isDirectory: true)
        let filename = environment["OPENCODE_DB"] ?? "opencode.db"
        guard filename != ":memory:" else { return nil }
        if filename.hasPrefix("/") {
            return URL(fileURLWithPath: filename)
        }
        return directory.appendingPathComponent(filename)
    }

    // MARK: - SQLite

    private struct MonthBounds {
        let anchorMs: Int64?
        let month: (startMs: Int64, endMs: Int64)
    }

    private static func monthAnchorBounds(databaseURL: URL, now: Date) -> MonthBounds? {
        guard let anchorMs = minCreatedMs(databaseURL: databaseURL) else {
            return nil
        }
        return MonthBounds(anchorMs: anchorMs, month: monthBounds(now: now, anchorMs: anchorMs))
    }

    private static func minCreatedMs(databaseURL: URL) -> Int64? {
        withDatabase(at: databaseURL) { db in
            let tables = try tableNames(db: db)
            let union = usageUnionSQL(
                hasMessages: tables.contains("message"),
                hasParts: tables.contains("part"),
                hasV2: tables.contains("session_message")
            )
            guard let union else { return nil }
            let sql = "WITH all_usage AS (\(union)) SELECT MIN(createdMs) FROM all_usage WHERE createdMs > 0 AND cost >= 0"
            return try scalarInt64(db: db, sql: sql)
        }
    }

    private static func aggregate(
        databaseURL: URL,
        now: Date,
        anchorMs: Int64?,
        month: (startMs: Int64, endMs: Int64)
    ) -> UsageQuotaSnapshot? {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let sessionStart = nowMs - Int64(fiveHours * 1000)
        let weekStartMs = Int64(startOfUTCWeek(now: now).timeIntervalSince1970 * 1000)
        let weekEndMs = weekStartMs + Int64(week * 1000)

        struct Totals {
            var sessionCost = 0.0
            var oldestSessionMs: Int64?
            var weeklyCost = 0.0
            var monthlyCost = 0.0
            var rowCount = 0
        }

        let totals: Totals? = withDatabase(at: databaseURL) { db in
            let tables = try tableNames(db: db)
            let union = usageUnionSQL(
                hasMessages: tables.contains("message"),
                hasParts: tables.contains("part"),
                hasV2: tables.contains("session_message")
            )
            guard let union else { return nil }
            // One scan buckets all three windows; params keep Swift memory flat.
            let sql = """
            WITH all_usage AS (\(union))
            SELECT
              SUM(CASE WHEN createdMs >= \(sessionStart) AND createdMs < \(nowMs) THEN cost ELSE 0 END),
              MIN(CASE WHEN createdMs >= \(sessionStart) AND createdMs < \(nowMs) THEN createdMs END),
              SUM(CASE WHEN createdMs >= \(weekStartMs) AND createdMs < \(weekEndMs) THEN cost ELSE 0 END),
              SUM(CASE WHEN createdMs >= \(month.startMs) AND createdMs < \(month.endMs) THEN cost ELSE 0 END),
              COUNT(*)
            FROM all_usage WHERE createdMs > 0 AND cost >= 0 AND cost = cost
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            var result = Totals()
            result.sessionCost = sqlite3_column_double(stmt, 0)
            if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                result.oldestSessionMs = sqlite3_column_int64(stmt, 1)
            }
            result.weeklyCost = sqlite3_column_double(stmt, 2)
            result.monthlyCost = sqlite3_column_double(stmt, 3)
            result.rowCount = Int(sqlite3_column_int(stmt, 4))
            return result
        }
        guard let totals, totals.rowCount > 0 else { return nil }

        let oldestSessionMs = totals.oldestSessionMs ?? nowMs
        let session = UsageWindow(
            remainingPercent: UsageQuotaFormatting.remainingPercent(
                fromUsed: percent(used: totals.sessionCost, limit: limits.session)
            ),
            resetAt: now.addingTimeInterval(TimeInterval(max(0, oldestSessionMs + Int64(fiveHours * 1000) - nowMs)) / 1000),
            label: "5h",
            durationSeconds: 5 * 3600
        )
        let weekly = UsageWindow(
            remainingPercent: UsageQuotaFormatting.remainingPercent(
                fromUsed: percent(used: totals.weeklyCost, limit: limits.weekly)
            ),
            resetAt: now.addingTimeInterval(TimeInterval(max(0, weekEndMs - nowMs)) / 1000),
            label: "7d",
            durationSeconds: 7 * 86400
        )
        let monthly = UsageWindow(
            remainingPercent: UsageQuotaFormatting.remainingPercent(
                fromUsed: percent(used: totals.monthlyCost, limit: limits.monthly)
            ),
            resetAt: now.addingTimeInterval(TimeInterval(max(0, month.endMs - nowMs)) / 1000),
            label: "30d",
            durationSeconds: 30 * 86400
        )
        _ = anchorMs
        return UsageQuotaSnapshot(
            providerID: .opencodeGo,
            displayName: UsageProviderID.opencodeGo.displayName,
            sessionWindow: session,
            weeklyWindow: weekly,
            tertiaryMonthlyWindow: monthly,
            isAvailable: true,
            statusNote: "local estimate — not account quota"
        )
    }

    private static func withDatabase<T>(at url: URL, read: (OpaquePointer?) throws -> T?) -> T? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        return try? read(db)
    }

    private static func tableNames(db: OpaquePointer?) throws -> Set<String> {
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        var names = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let bytes = sqlite3_column_text(stmt, 0) {
                names.insert(String(cString: bytes))
            }
        }
        return names
    }

    private static func scalarInt64(db: OpaquePointer?, sql: String) throws -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
        let value = sqlite3_column_int64(stmt, 0)
        return value > 0 ? value : nil
    }

    // MARK: - Usage union (same predicates as CodexBar)

    private static func usageUnionSQL(hasMessages: Bool, hasParts: Bool, hasV2: Bool) -> String? {
        guard hasMessages || hasV2 else { return nil }
        let legacy = hasMessages
            ? (hasParts ? messageAndPartUsageSQL
                : "SELECT createdMs, cost, messageID FROM (\(providerMessagesSQL)) WHERE hasCost")
            : "SELECT NULL AS createdMs, NULL AS cost, NULL AS messageID WHERE 0"
        return """
        WITH legacy_usage AS (\(legacy))
        SELECT createdMs, cost FROM legacy_usage
        \(hasV2 ? sessionMessageUsageSQL : "")
        """
    }

    private static let providerMessagesSQL = """
        SELECT
          id AS messageID,
          CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs,
          CAST(json_extract(data, '$.cost') AS REAL) AS cost,
          json_type(data, '$.cost') IN ('integer', 'real') AS hasCost
        FROM message
        WHERE json_valid(data)
          AND json_extract(data, '$.providerID') = 'opencode-go'
          AND json_extract(data, '$.role') = 'assistant'
    """

    private static let messageAndPartUsageSQL = """
        WITH provider_messages AS (\(providerMessagesSQL))
        SELECT
          CASE WHEN p.message_id IS NULL THEN m.createdMs ELSE
            CAST(COALESCE(json_extract(p.data, '$.time.created'), p.time_created, m.createdMs) AS INTEGER)
            END AS createdMs,
          CASE WHEN p.message_id IS NULL THEN m.cost ELSE CAST(json_extract(p.data, '$.cost') AS REAL) END AS cost,
          m.messageID AS messageID
        FROM provider_messages m
        LEFT JOIN part p ON m.messageID = p.message_id
          AND CASE WHEN substr(p.data, 1, 15) IN ('{"type":"tool",', '{"type":"text",')
            THEN 0 WHEN json_valid(p.data) THEN
              json_extract(p.data, '$.type') = 'step-finish'
              AND json_type(p.data, '$.cost') IN ('integer', 'real') ELSE 0 END
        WHERE p.message_id IS NOT NULL OR m.hasCost
    """

    private static let sessionMessageUsageSQL = """
        UNION ALL
        SELECT
          CAST(COALESCE(json_extract(s.data, '$.time.created'), s.time_created) AS INTEGER) AS createdMs,
          CAST(json_extract(s.data, '$.cost') AS REAL) AS cost
        FROM session_message s
        WHERE s.type IN ('assistant', 'compaction')
          AND json_valid(s.data)
          AND json_extract(s.data, '$.model.providerID') = 'opencode-go'
          AND json_type(s.data, '$.cost') IN ('integer', 'real')
          AND NOT EXISTS (
            SELECT 1 FROM legacy_usage m WHERE m.messageID = s.id
              AND m.createdMs > 0 AND m.cost >= 0)
    """

    // MARK: - Windows (same boundaries as CodexBar)

    private static func percent(used: Double, limit: Double) -> Double {
        guard used.isFinite, limit > 0 else { return 0 }
        return max(0, min(100, used / limit * 100))
    }

    private static func startOfUTCWeek(now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return calendar.date(from: components) ?? now
    }

    private static func monthBounds(now: Date, anchorMs: Int64?) -> (startMs: Int64, endMs: Int64) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current

        guard let anchorMs else {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
        }

        let anchor = Date(timeIntervalSince1970: TimeInterval(anchorMs) / 1000)
        let anchorComponents = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: anchor)

        var startMonthComponents = calendar.dateComponents([.year, .month], from: now)
        var start = anchoredMonth(calendar: calendar, month: startMonthComponents, anchor: anchorComponents)
        if start > now, let previous = calendar.date(byAdding: .month, value: -1, to: start) {
            startMonthComponents = calendar.dateComponents([.year, .month], from: previous)
            start = anchoredMonth(calendar: calendar, month: startMonthComponents, anchor: anchorComponents)
        }
        let end = anchoredMonth(
            calendar: calendar,
            month: monthComponents(after: startMonthComponents, calendar: calendar),
            anchor: anchorComponents
        )
        return (Int64(start.timeIntervalSince1970 * 1000), Int64(end.timeIntervalSince1970 * 1000))
    }

    private static func monthComponents(after month: DateComponents, calendar: Calendar) -> DateComponents {
        let monthStart = calendar.date(from: month) ?? Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return calendar.dateComponents([.year, .month], from: nextMonth)
    }

    private static func anchoredMonth(calendar: Calendar, month: DateComponents, anchor: DateComponents) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = month.year
        components.month = month.month
        components.day = anchor.day
        components.hour = anchor.hour
        components.minute = anchor.minute
        components.second = anchor.second
        components.nanosecond = anchor.nanosecond

        if let date = calendar.date(from: components),
           calendar.component(.month, from: date) == month.month
        {
            return date
        }
        components.day = calendar.range(of: .day, in: .month, for: calendar.date(from: month) ?? Date())?.count
        return calendar.date(from: components) ?? Date()
    }
}
