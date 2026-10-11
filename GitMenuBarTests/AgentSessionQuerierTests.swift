@testable import GitMenuBar
import SQLite3
import XCTest

final class AgentSessionQuerierTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let uniqueName = "AgentSessionQuerierTests_\(UUID().uuidString)"
        temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Filesystem & SQLite Session Tests

    func testClaudeAndCursorRecentDetectionFromFilesystem() async throws {
        let projectPath = "/Users/test/workspace/myApp"
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let oneHourAgo = fixedNow.addingTimeInterval(-3600)
        let threeHoursAgo = fixedNow.addingTimeInterval(-3 * 3600)

        let claudeDir = temporaryDirectoryURL.appendingPathComponent("claude_projects")
        let cursorDir = temporaryDirectoryURL.appendingPathComponent("cursor_projects")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)

        let claudeProjectDir = claudeDir.appendingPathComponent("-Users-test-workspace-myApp")
        try FileManager.default.createDirectory(at: claudeProjectDir, withIntermediateDirectories: true)
        let sessionFile = claudeProjectDir.appendingPathComponent("session.jsonl")
        try Data("dummy".utf8).write(to: sessionFile)
        try FileManager.default.setAttributes([.modificationDate: oneHourAgo], ofItemAtPath: sessionFile.path)
        try FileManager.default.setAttributes([.modificationDate: oneHourAgo], ofItemAtPath: claudeProjectDir.path)

        let cursorProjectDir = cursorDir.appendingPathComponent("Users-test-workspace-myApp")
        try FileManager.default.createDirectory(at: cursorProjectDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: threeHoursAgo], ofItemAtPath: cursorProjectDir.path)

        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: claudeDir,
            cursorProjectsDirectory: cursorDir,
            codexDatabaseURL: temporaryDirectoryURL.appendingPathComponent("nonexistent_codex.sqlite"),
            opencodeDatabaseURL: temporaryDirectoryURL.appendingPathComponent("nonexistent_opencode.db")
        )

        let result = await querier.recentActivities(for: [projectPath], now: fixedNow)
        let activities = result[projectPath] ?? []

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.harness, .claudeCode)
        if case let .recent(date) = activities.first?.status {
            XCTAssertEqual(date.timeIntervalSince1970, oneHourAgo.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("Expected .recent status")
        }
    }

    func testCodexSQLiteRecentDetection() async throws {
        let projectPath = "/Users/test/workspace/codexApp"
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let thirtyMinsAgo = fixedNow.addingTimeInterval(-1800)

        let dbURL = temporaryDirectoryURL.appendingPathComponent("state_5.sqlite")
        try createCodexFixtureDatabase(
            at: dbURL,
            rows: [
                (cwd: projectPath, updatedAt: Int64(thirtyMinsAgo.timeIntervalSince1970)),
                (cwd: "/other/project", updatedAt: Int64(fixedNow.timeIntervalSince1970))
            ]
        )

        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("no_claude"),
            cursorProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("no_cursor"),
            codexDatabaseURL: dbURL,
            opencodeDatabaseURL: temporaryDirectoryURL.appendingPathComponent("no_opencode")
        )

        let result = await querier.recentActivities(for: [projectPath], now: fixedNow)
        let activities = result[projectPath] ?? []

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.harness, .codex)
        if case let .recent(date) = activities.first?.status {
            XCTAssertEqual(date.timeIntervalSince1970, thirtyMinsAgo.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("Expected .recent status")
        }
    }

    func testOpenCodeSQLiteRecentDetection() async throws {
        let projectPath = "/Users/test/workspace/opencodeApp"
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let fortyMinsAgo = fixedNow.addingTimeInterval(-2400)
        let fortyMinsAgoMs = Int64(fortyMinsAgo.timeIntervalSince1970 * 1000)

        let dbURL = temporaryDirectoryURL.appendingPathComponent("opencode.db")
        try createOpenCodeFixtureDatabase(
            at: dbURL,
            rows: [
                (directory: projectPath, timeUpdated: fortyMinsAgoMs)
            ]
        )

        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("no_claude"),
            cursorProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("no_cursor"),
            codexDatabaseURL: temporaryDirectoryURL.appendingPathComponent("no_codex"),
            opencodeDatabaseURL: dbURL
        )

        let result = await querier.recentActivities(for: [projectPath], now: fixedNow)
        let activities = result[projectPath] ?? []

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.harness, .opencode)
        if case let .recent(date) = activities.first?.status {
            XCTAssertEqual(date.timeIntervalSince1970, fortyMinsAgo.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("Expected .recent status")
        }
    }

    func testCodexAndOpenCodeSubdirectoryMatchingInSQLite() async throws {
        let projectPath = "/Users/test/workspace/monorepo"
        let subPath = projectPath + "/packages/backend"
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let thirtyMinsAgo = fixedNow.addingTimeInterval(-1800)
        let thirtyMinsAgoMs = Int64(thirtyMinsAgo.timeIntervalSince1970 * 1000)

        let codexDb = temporaryDirectoryURL.appendingPathComponent("codex_subdir.sqlite")
        try createCodexFixtureDatabase(
            at: codexDb,
            rows: [
                (cwd: subPath, updatedAt: Int64(thirtyMinsAgo.timeIntervalSince1970))
            ]
        )

        let opencodeDb = temporaryDirectoryURL.appendingPathComponent("opencode_subdir.db")
        try createOpenCodeFixtureDatabase(
            at: opencodeDb,
            rows: [
                (directory: subPath, timeUpdated: thirtyMinsAgoMs)
            ]
        )

        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("no_claude"),
            cursorProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("no_cursor"),
            codexDatabaseURL: codexDb,
            opencodeDatabaseURL: opencodeDb
        )

        let result = await querier.recentActivities(for: [projectPath], now: fixedNow)
        let activities = result[projectPath] ?? []

        XCTAssertEqual(activities.count, 2)
        let harnesses = Set(activities.map(\.harness))
        XCTAssertTrue(harnesses.contains(.codex))
        XCTAssertTrue(harnesses.contains(.opencode))
    }

    func testGeminiDirectoryDoesNotSignalAntigravity() async throws {
        let projectDir = temporaryDirectoryURL.appendingPathComponent("testProject")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let geminiDir = projectDir.appendingPathComponent(".gemini")
        try FileManager.default.createDirectory(at: geminiDir, withIntermediateDirectories: true)

        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let fifteenMinsAgo = fixedNow.addingTimeInterval(-900)
        try FileManager.default.setAttributes([.modificationDate: fifteenMinsAgo], ofItemAtPath: geminiDir.path)

        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("no_claude"),
            cursorProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("no_cursor"),
            codexDatabaseURL: temporaryDirectoryURL.appendingPathComponent("no_codex"),
            opencodeDatabaseURL: temporaryDirectoryURL.appendingPathComponent("no_opencode")
        )

        let result = await querier.recentActivities(for: [projectDir.path], now: fixedNow)
        let activities = result[projectDir.path] ?? []

        XCTAssertTrue(activities.isEmpty)
    }

    func testDatabaseCycleFindsProjectsBeyondFiftyRowsAndDiscoversHighestVersion() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let path = "/tmp/quiet-project"
        let busyRows = (0 ..< 60).map { _ in (cwd: "/tmp/busy-project", updatedAt: Int64(now.timeIntervalSince1970)) }
        try createCodexFixtureDatabase(
            at: temporaryDirectoryURL.appendingPathComponent("state_12.sqlite"),
            rows: busyRows + [(cwd: path, updatedAt: Int64(now.timeIntervalSince1970 - 1800))]
        )
        try createCodexFixtureDatabase(at: temporaryDirectoryURL.appendingPathComponent("state_9.sqlite"), rows: [])
        let openCode = temporaryDirectoryURL.appendingPathComponent("opencode.db")
        try createOpenCodeFixtureDatabase(
            at: openCode,
            rows: busyRows.map { (directory: $0.cwd, timeUpdated: $0.updatedAt * 1000) }
                + [(directory: path, timeUpdated: Int64((now.timeIntervalSince1970 - 1800) * 1000))]
        )
        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("missing"),
            cursorProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("missing"),
            codexDirectory: temporaryDirectoryURL, opencodeDatabaseURL: openCode
        )
        let results = await querier.recentActivities(for: [path, "/tmp/busy-project"], now: now)
        for project in [path, "/tmp/busy-project"] {
            XCTAssertEqual(Set((results[project] ?? []).map(\.harness)), [.codex, .opencode])
        }
    }

    func testUnknownLatestCodexSchemaFailsClosedWithoutFallingBack() async throws {
        let now = Date()
        try createCodexFixtureDatabase(
            at: temporaryDirectoryURL.appendingPathComponent("state_5.sqlite"),
            rows: [(cwd: "/tmp/project", updatedAt: Int64(now.timeIntervalSince1970))]
        )
        try Data().write(to: temporaryDirectoryURL.appendingPathComponent("state_6.sqlite"))
        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("missing"),
            cursorProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("missing"),
            codexDirectory: temporaryDirectoryURL,
            opencodeDatabaseURL: temporaryDirectoryURL.appendingPathComponent("missing")
        )
        let results = await querier.recentActivities(for: ["/tmp/project"], now: now)
        XCTAssertEqual(results["/tmp/project"], [])
    }

    func testProjectSlugsDoNotMatchLongerProjectNames() async throws {
        let now = Date()
        let claude = temporaryDirectoryURL.appendingPathComponent("claude")
        let cursor = temporaryDirectoryURL.appendingPathComponent("cursor")
        for base in [claude, cursor] {
            let project = base.appendingPathComponent("-a-bc")
            let transcriptDirectory = base == cursor ? project.appendingPathComponent("agent-transcripts/session") : project
            try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
            try Data().write(to: transcriptDirectory.appendingPathComponent("session.jsonl"))
        }
        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: claude, cursorProjectsDirectory: cursor,
            codexDatabaseURL: temporaryDirectoryURL.appendingPathComponent("missing"),
            opencodeDatabaseURL: temporaryDirectoryURL.appendingPathComponent("missing")
        )
        let results = await querier.recentActivities(for: ["/a/b", "/a/bc"], now: now)
        XCTAssertEqual(results["/a/b"], [])
        XCTAssertEqual(Set((results["/a/bc"] ?? []).map(\.harness)), [.claudeCode, .cursor])
    }

    func testCursorIDEFilesDoNotSignalRecentButNestedAgentTranscriptDoes() async throws {
        let now = Date()
        let path = "/tmp/cursor-project"
        let cursor = temporaryDirectoryURL.appendingPathComponent("cursor")
        let project = cursor.appendingPathComponent("-tmp-cursor-project")
        let terminals = project.appendingPathComponent("terminals")
        try FileManager.default.createDirectory(at: terminals, withIntermediateDirectories: true)
        try Data().write(to: terminals.appendingPathComponent("terminal.jsonl"))
        let querier = SystemAgentSessionQuerier(
            claudeProjectsDirectory: temporaryDirectoryURL.appendingPathComponent("missing"),
            cursorProjectsDirectory: cursor,
            codexDatabaseURL: temporaryDirectoryURL.appendingPathComponent("missing"),
            opencodeDatabaseURL: temporaryDirectoryURL.appendingPathComponent("missing")
        )
        let ideOnly = await querier.recentActivities(for: [path], now: now)
        XCTAssertEqual(ideOnly[path], [])
        let transcripts = project.appendingPathComponent("agent-transcripts/session/subagents")
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        try Data().write(to: transcripts.appendingPathComponent("agent.jsonl"))
        let agentSession = await querier.recentActivities(for: [path], now: now)
        XCTAssertEqual(agentSession[path]?.map(\.harness), [.cursor])
    }

    func testAgentProjectActivityAccessibilityDescription() {
        let runningActivity = AgentProjectActivity(harness: .cursor, status: .running)
        XCTAssertEqual(runningActivity.accessibilityDescription, "Cursor agent active")

        let recentActivity = AgentProjectActivity(harness: .codex, status: .recent(Date()))
        XCTAssertEqual(recentActivity.accessibilityDescription, "Codex agent recent")
    }

    // MARK: - SQLite Fixture Helpers

    private func createCodexFixtureDatabase(at url: URL, rows: [(cwd: String, updatedAt: Int64)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw XCTSkip("Unable to create SQLite database")
        }
        defer { sqlite3_close(db) }

        let createTable = "CREATE TABLE threads (id TEXT PRIMARY KEY, cwd TEXT, updated_at INTEGER)"
        guard sqlite3_exec(db, createTable, nil, nil, nil) == SQLITE_OK else {
            throw XCTSkip("Failed to create threads table")
        }

        let insert = "INSERT INTO threads (id, cwd, updated_at) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw XCTSkip("Failed to prepare insert")
        }
        defer { sqlite3_finalize(stmt) }

        for (index, row) in rows.enumerated() {
            let id = "thread_\(index)"
            sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, row.cwd, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int64(stmt, 3, row.updatedAt)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
    }

    private func createOpenCodeFixtureDatabase(at url: URL, rows: [(directory: String, timeUpdated: Int64)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw XCTSkip("Unable to create SQLite database")
        }
        defer { sqlite3_close(db) }

        let createTable = "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT, time_updated INTEGER)"
        guard sqlite3_exec(db, createTable, nil, nil, nil) == SQLITE_OK else {
            throw XCTSkip("Failed to create session_v2 table")
        }

        let insert = "INSERT INTO session_v2 (id, directory, time_updated) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw XCTSkip("Failed to prepare insert")
        }
        defer { sqlite3_finalize(stmt) }

        for (index, row) in rows.enumerated() {
            let id = "session_\(index)"
            sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, row.directory, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int64(stmt, 3, row.timeUpdated)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
    }
}
