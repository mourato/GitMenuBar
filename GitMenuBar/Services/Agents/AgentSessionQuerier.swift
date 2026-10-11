import Foundation
import OSLog
import SQLite3

// MARK: - Session Querying Protocol

protocol AgentSessionQuerying: Sendable {
    func recentActivities(for projectPaths: [String], now: Date) async -> [String: [AgentProjectActivity]]
}

// MARK: - System Agent Session Querier

struct SystemAgentSessionQuerier: AgentSessionQuerying {
    let claudeProjectsDirectory: URL
    let cursorProjectsDirectory: URL
    private let codexDatabaseURL: URL?
    private let codexDirectory: URL
    let opencodeDatabaseURL: URL

    static let defaultClaudeProjectsDirectory = URL(
        fileURLWithPath: NSString(string: "~/.claude/projects").expandingTildeInPath
    )
    static let defaultCursorProjectsDirectory = URL(
        fileURLWithPath: NSString(string: "~/.cursor/projects").expandingTildeInPath
    )
    static let defaultCodexDirectory = URL(
        fileURLWithPath: NSString(string: "~/.codex").expandingTildeInPath
    )
    static let defaultOpenCodeDatabaseURL = URL(
        fileURLWithPath: NSString(string: "~/.local/share/opencode/opencode.db").expandingTildeInPath
    )
    init(
        claudeProjectsDirectory: URL = defaultClaudeProjectsDirectory,
        cursorProjectsDirectory: URL = defaultCursorProjectsDirectory,
        codexDatabaseURL: URL? = nil,
        codexDirectory: URL = defaultCodexDirectory,
        opencodeDatabaseURL: URL = defaultOpenCodeDatabaseURL
    ) {
        self.claudeProjectsDirectory = claudeProjectsDirectory
        self.cursorProjectsDirectory = cursorProjectsDirectory
        self.codexDatabaseURL = codexDatabaseURL
        self.codexDirectory = codexDirectory
        self.opencodeDatabaseURL = opencodeDatabaseURL
    }

    func recentActivities(for projectPaths: [String], now: Date) async -> [String: [AgentProjectActivity]] {
        let task = Task.detached(priority: .utility) { scanSessions(for: projectPaths, now: now) }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func scanSessions(for projectPaths: [String], now: Date) -> [String: [AgentProjectActivity]] {
        guard !Task.isCancelled, !projectPaths.isEmpty else { return [:] }
        let codex = databaseActivities(
            at: codexDatabaseURL ?? discoverCodexDatabase(),
            queries: ["SELECT cwd, updated_at FROM threads WHERE updated_at >= ?1"],
            projectPaths: projectPaths, now: now
        )
        let opencode = databaseActivities(
            at: opencodeDatabaseURL,
            queries: ["session_v2", "session"].map {
                "SELECT directory, time_updated FROM \($0) "
                    + "WHERE (time_updated <= 10000000000 AND time_updated >= ?1) "
                    + "OR (time_updated > 10000000000 AND time_updated >= ?2)"
            }, projectPaths: projectPaths, now: now
        )
        var results: [String: [AgentProjectActivity]] = [:]
        for projectPath in projectPaths {
            guard !Task.isCancelled else { return [:] }
            var activities: [AgentProjectActivity] = []
            if let date = findRecentProjectDirectory(in: claudeProjectsDirectory, projectPath: projectPath, now: now) {
                activities.append(AgentProjectActivity(harness: .claudeCode, status: .recent(date)))
            }
            if let date = findRecentProjectDirectory(in: cursorProjectsDirectory, projectPath: projectPath, now: now, transcriptsSubdirectory: "agent-transcripts") {
                activities.append(AgentProjectActivity(harness: .cursor, status: .recent(date)))
            }
            if let date = codex[projectPath] {
                activities.append(AgentProjectActivity(harness: .codex, status: .recent(date)))
            }
            if let date = opencode[projectPath] {
                activities.append(AgentProjectActivity(harness: .opencode, status: .recent(date)))
            }
            results[projectPath] = activities
        }
        return results
    }

    private func findRecentProjectDirectory(
        in baseDirectory: URL, projectPath: String, now: Date, transcriptsSubdirectory: String? = nil
    ) -> Date? {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: baseDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        let candidateSlugs = AgentActivityDetector.candidateSlugs(for: projectPath)
        var latestDate: Date?

        for slug in candidateSlugs {
            guard !Task.isCancelled else { return nil }
            let projectURL = baseDirectory.appendingPathComponent(slug)
            let candidateURL = transcriptsSubdirectory.map { projectURL.appendingPathComponent($0) } ?? projectURL
            guard fileManager.fileExists(atPath: candidateURL.path) else { continue }
            if let mtime = latestTranscriptDate(at: candidateURL, fileManager: fileManager) {
                if latestDate == nil || mtime > (latestDate ?? .distantPast) {
                    latestDate = mtime
                }
            }
        }
        guard let latest = latestDate else { return nil }
        return AgentActivityDetector.isWithinRecentThreshold(date: latest, relativeTo: now) ? latest : nil
    }

    private func latestTranscriptDate(at url: URL, fileManager: FileManager) -> Date? {
        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        var latest: Date?
        for case let item as URL in enumerator {
            guard !Task.isCancelled else { return nil }
            guard item.pathExtension == "jsonl",
                  let values = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let date = values.contentModificationDate else { continue }
            latest = max(latest ?? .distantPast, date)
        }
        return latest
    }

    private func discoverCodexDatabase() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: codexDirectory, includingPropertiesForKeys: nil)) ?? []
        let candidates = files.compactMap { url -> (Int, URL)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst(6).dropLast(7)) else { return nil }
            return (version, url)
        }
        guard let latest = candidates.max(by: { $0.0 < $1.0 }) else {
            Logger(subsystem: "GitMenuBar", category: "AgentActivity").debug("Codex state database unavailable")
            return nil
        }
        return latest.1
    }

    private func databaseActivities(
        at url: URL?, queries: [String], projectPaths: [String], now: Date
    ) -> [String: Date] {
        guard !Task.isCancelled, let url, FileManager.default.fileExists(atPath: url.path) else { return [:] }
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil)
        guard let database = connection else { return [:] }
        defer { sqlite3_close(database) }
        guard status == SQLITE_OK else { return [:] }
        sqlite3_busy_timeout(database, 200)
        var results: [String: Date] = [:]
        var confirmedSchema = false
        for query in queries {
            guard !Task.isCancelled else { return [:] }
            guard let rows = recentRows(database: database, query: query, now: now) else { continue }
            confirmedSchema = true
            for (path, date) in rows {
                for project in projectPaths where AgentActivityDetector.isMatchingPath(processCwd: path, projectPath: project) {
                    results[project] = max(results[project] ?? .distantPast, date)
                }
            }
        }
        if !confirmedSchema {
            Logger(subsystem: "GitMenuBar", category: "AgentActivity").debug("Agent database schema unavailable; recent signal omitted")
        }
        return results
    }

    private func recentRows(database: OpaquePointer, query: String, now: Date) -> [(String, Date)]? {
        var prepared: OpaquePointer?
        let status = sqlite3_prepare_v2(database, query, -1, &prepared, nil)
        guard let statement = prepared else { return nil }
        defer { sqlite3_finalize(statement) }
        guard status == SQLITE_OK else { return nil }
        let cutoff = Int64(now.timeIntervalSince1970 - AgentActivityDetector.recentWindowSeconds)
        sqlite3_bind_int64(statement, 1, cutoff)
        sqlite3_bind_int64(statement, 2, cutoff * 1000)
        var rows: [(String, Date)] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            guard !Task.isCancelled else { return nil }
            if let pathBytes = sqlite3_column_text(statement, 0) {
                let date = AgentActivityDetector.parseEpochTimestamp(rawTime: sqlite3_column_int64(statement, 1))
                if AgentActivityDetector.isWithinRecentThreshold(date: date, relativeTo: now) {
                    rows.append((String(cString: pathBytes), date))
                }
            }
            step = sqlite3_step(statement)
        }
        return step == SQLITE_DONE ? rows : nil
    }
}
