import Foundation
import SQLite3

// MARK: - Session Querying Protocol

public protocol AgentSessionQuerying: Sendable {
    func recentActivities(for projectPaths: [String], now: Date) async -> [String: [AgentProjectActivity]]
}

// MARK: - System Agent Session Querier

public final class SystemAgentSessionQuerier: AgentSessionQuerying, @unchecked Sendable {
    public let claudeProjectsDirectory: URL
    public let cursorProjectsDirectory: URL
    public let codexDatabaseURL: URL
    public let opencodeDatabaseURL: URL

    public static let defaultClaudeProjectsDirectory = URL(
        fileURLWithPath: NSString(string: "~/.claude/projects").expandingTildeInPath
    )
    public static let defaultCursorProjectsDirectory = URL(
        fileURLWithPath: NSString(string: "~/.cursor/projects").expandingTildeInPath
    )
    public static let defaultCodexDatabaseURL = URL(
        fileURLWithPath: NSString(string: "~/.codex/state_5.sqlite").expandingTildeInPath
    )
    public static let defaultOpenCodeDatabaseURL = URL(
        fileURLWithPath: NSString(string: "~/.local/share/opencode/opencode.db").expandingTildeInPath
    )
    public init(
        claudeProjectsDirectory: URL = defaultClaudeProjectsDirectory,
        cursorProjectsDirectory: URL = defaultCursorProjectsDirectory,
        codexDatabaseURL: URL = defaultCodexDatabaseURL,
        opencodeDatabaseURL: URL = defaultOpenCodeDatabaseURL
    ) {
        self.claudeProjectsDirectory = claudeProjectsDirectory
        self.cursorProjectsDirectory = cursorProjectsDirectory
        self.codexDatabaseURL = codexDatabaseURL
        self.opencodeDatabaseURL = opencodeDatabaseURL
    }

    public func recentActivities(for projectPaths: [String], now: Date) async -> [String: [AgentProjectActivity]] {
        await Task.detached(priority: .userInitiated) {
            self.scanSessions(for: projectPaths, now: now)
        }.value
    }

    private func scanSessions(for projectPaths: [String], now: Date) -> [String: [AgentProjectActivity]] {
        var results: [String: [AgentProjectActivity]] = [:]
        for projectPath in projectPaths {
            var activities: [AgentProjectActivity] = []
            if let date = findRecentProjectDirectory(in: claudeProjectsDirectory, projectPath: projectPath, now: now) {
                activities.append(AgentProjectActivity(harness: .claudeCode, status: .recent(date)))
            }
            if let date = findRecentProjectDirectory(in: cursorProjectsDirectory, projectPath: projectPath, now: now) {
                activities.append(AgentProjectActivity(harness: .cursor, status: .recent(date)))
            }
            if let date = checkCodexRecent(for: projectPath, now: now) {
                activities.append(AgentProjectActivity(harness: .codex, status: .recent(date)))
            }
            if let date = checkOpenCodeRecent(for: projectPath, now: now) {
                activities.append(AgentProjectActivity(harness: .opencode, status: .recent(date)))
            }
            results[projectPath] = activities
        }
        return results
    }

    private func findRecentProjectDirectory(in baseDirectory: URL, projectPath: String, now: Date) -> Date? {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: baseDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        let candidateSlugs = AgentActivityDetector.candidateSlugs(for: projectPath)
        var latestDate: Date?

        for slug in candidateSlugs {
            let candidateURL = baseDirectory.appendingPathComponent(slug)
            guard fileManager.fileExists(atPath: candidateURL.path) else { continue }
            if let mtime = latestModificationDate(at: candidateURL, fileManager: fileManager) {
                if latestDate == nil || mtime > (latestDate ?? .distantPast) {
                    latestDate = mtime
                }
            }
        }
        guard let latest = latestDate else { return nil }
        return AgentActivityDetector.isWithinRecentThreshold(date: latest, relativeTo: now) ? latest : nil
    }

    private func latestModificationDate(at url: URL, fileManager: FileManager) -> Date? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        var latest = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date

        if isDir.boolValue,
           let contents = try? fileManager.contentsOfDirectory(
               at: url,
               includingPropertiesForKeys: [.contentModificationDateKey],
               options: [.skipsHiddenFiles]
           )
        {
            for item in contents {
                if let mod = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    if latest == nil || mod > (latest ?? .distantPast) {
                        latest = mod
                    }
                }
            }
        }
        return latest
    }

    private func checkCodexRecent(for projectPath: String, now: Date) -> Date? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: codexDatabaseURL.path) else { return nil }

        var database: OpaquePointer?
        guard sqlite3_open_v2(codexDatabaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database
        else {
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 200)

        let cutoffSeconds = Int64(now.timeIntervalSince1970 - AgentActivityDetector.recentWindowSeconds)
        let query = "SELECT cwd, updated_at FROM threads WHERE updated_at >= ?1 ORDER BY updated_at DESC LIMIT 50"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, cutoffSeconds)

        var latestDate: Date?
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cwdPtr = sqlite3_column_text(statement, 0) else { continue }
            let sessionCwd = String(cString: cwdPtr)
            guard AgentActivityDetector.isMatchingPath(processCwd: sessionCwd, projectPath: projectPath) else {
                continue
            }
            let rawUpdatedAt = sqlite3_column_int64(statement, 1)
            guard rawUpdatedAt > 0 else { continue }
            let date = AgentActivityDetector.parseEpochTimestamp(rawTime: rawUpdatedAt)
            if AgentActivityDetector.isWithinRecentThreshold(date: date, relativeTo: now) {
                if latestDate == nil || date > (latestDate ?? .distantPast) {
                    latestDate = date
                }
            }
        }
        return latestDate
    }

    private func checkOpenCodeRecent(for projectPath: String, now: Date) -> Date? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: opencodeDatabaseURL.path) else { return nil }

        var database: OpaquePointer?
        guard sqlite3_open_v2(opencodeDatabaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database
        else {
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 200)

        let cutoffSeconds = Int64(now.timeIntervalSince1970 - AgentActivityDetector.recentWindowSeconds)
        let cutoffMs = cutoffSeconds * 1000
        var latestDate: Date?

        for tableName in ["session_v2", "session"] {
            let query = """
            SELECT directory, time_updated FROM \(tableName)
            WHERE time_updated >= ?1 OR time_updated >= ?2
            ORDER BY time_updated DESC LIMIT 50
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
                continue
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, cutoffSeconds)
            sqlite3_bind_int64(statement, 2, cutoffMs)

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let dirPtr = sqlite3_column_text(statement, 0) else { continue }
                let sessionDir = String(cString: dirPtr)
                guard AgentActivityDetector.isMatchingPath(processCwd: sessionDir, projectPath: projectPath) else {
                    continue
                }
                let rawTime = sqlite3_column_int64(statement, 1)
                guard rawTime > 0 else { continue }
                let date = AgentActivityDetector.parseEpochTimestamp(rawTime: rawTime)
                if AgentActivityDetector.isWithinRecentThreshold(date: date, relativeTo: now) {
                    if latestDate == nil || date > (latestDate ?? .distantPast) {
                        latestDate = date
                    }
                }
            }
        }

        return latestDate
    }
}
