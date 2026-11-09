@testable import GitMenuBar
import SQLite3
import XCTest

final class OpenCodeGoUsageTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - API parsing (ported expectations from CodexBar's parseAPIUsage)

    func testAPIParsingMapsRollingWeeklyMonthly() throws {
        let json = """
        {"usage":{
            "rolling":{"percent":12,"resetsAt":"2026-08-12T02:00:00.000Z"},
            "weekly":{"percent":8,"resetsAt":"2026-08-18T00:00:00.000Z"},
            "monthly":{"percent":35,"resetsAt":"2026-09-01T00:00:00.000Z"}
        }}
        """
        let snapshot = try XCTUnwrap(OpenCodeGoUsageParsing.snapshot(
            fromAPIData: Data(json.utf8),
            now: Date(timeIntervalSince1970: 1_786_493_600)
        ))

        XCTAssertEqual(snapshot.providerID, .opencodeGo)
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 88)
        XCTAssertEqual(snapshot.sessionWindow?.label, "5h")
        XCTAssertEqual(snapshot.sessionWindow?.durationSeconds, 5 * 3600)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 92)
        XCTAssertEqual(snapshot.tertiaryMonthlyWindow?.remainingPercent, 65)
        XCTAssertEqual(snapshot.tertiaryMonthlyWindow?.label, "30d")
        XCTAssertEqual(snapshot.statusNote, "opencode go usage api")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(snapshot.sessionWindow?.resetAt, formatter.date(from: "2026-08-12T02:00:00.000Z"))
        XCTAssertEqual(snapshot.weeklyWindow?.resetAt, formatter.date(from: "2026-08-18T00:00:00.000Z"))
        XCTAssertEqual(snapshot.tertiaryMonthlyWindow?.resetAt, formatter.date(from: "2026-09-01T00:00:00.000Z"))
    }

    func testAPIParsingWithoutWeeklyMonthly() throws {
        let json = """
        {"usage":{"rolling":{"percent":50,"resetsAt":"2026-08-12T02:00:00Z"}}}
        """
        let snapshot = try XCTUnwrap(OpenCodeGoUsageParsing.snapshot(
            fromAPIData: Data(json.utf8),
            now: Date(timeIntervalSince1970: 1_786_493_600)
        ))

        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 50)
        XCTAssertNil(snapshot.weeklyWindow)
        XCTAssertNil(snapshot.tertiaryMonthlyWindow)
    }

    func testAPIParsingRejectsUnparsableWeekly() {
        let json = """
        {"usage":{"rolling":{"percent":10},"weekly":{"note":"no meters"}}}
        """
        XCTAssertNil(OpenCodeGoUsageParsing.snapshot(
            fromAPIData: Data(json.utf8),
            now: Date(timeIntervalSince1970: 1_786_493_600)
        ))
    }

    // MARK: - Provider: API first

    func testProviderSendsBearerTokenToUsageEndpoint() async {
        let capturedAuth = PromptCapture()
        let capturedPath = PromptCapture()
        MockURLProtocol.requestHandler = { request in
            capturedAuth.set(request.value(forHTTPHeaderField: "Authorization") ?? "")
            capturedPath.set(request.url?.path ?? "")
            let body = """
            {"usage":{"rolling":{"percent":20,"resetsAt":"2026-08-12T02:00:00.000Z"}}}
            """
            return try (makeMockHTTPResponse(for: request), Data(body.utf8))
        }

        let provider = OpenCodeGoUsageProvider(
            urlSession: makeMockedURLSession(),
            keyStore: InMemoryAIAPIKeyStore(),
            environment: ["OPENCODE_API_KEY": "go_secret"],
            homeDirectory: FileManager.default.temporaryDirectory,
            now: { Date(timeIntervalSince1970: 1_786_493_600) }
        )
        let snapshot = await provider.fetchSnapshot()

        XCTAssertEqual(capturedPath.value, "/zen/go/v1/usage")
        XCTAssertEqual(capturedAuth.value, "Bearer go_secret")
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 80)
        XCTAssertEqual(snapshot.statusNote, "opencode go usage api")
    }

    func testProviderSurfacesInvalidCredentialsWithoutLocalMasking() async throws {
        let home = try makeTemporaryTestDirectory(testName: "OpenCodeGoInvalidCredentials")
        try Self.createLegacyDatabase(at: home.appendingPathComponent("opencode.db"), rows: [
            (createdMs: 1_786_490_000_000, cost: 6.0)
        ])
        let opencodeHome = try makeTemporaryTestDirectory(testName: "OpenCodeGoInvalidHome")
        try FileManager.default.createDirectory(
            at: opencodeHome.appendingPathComponent(".local/share/opencode"),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: home.appendingPathComponent("opencode.db"),
            to: opencodeHome.appendingPathComponent(".local/share/opencode/opencode.db")
        )

        MockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        let provider = OpenCodeGoUsageProvider(
            urlSession: makeMockedURLSession(),
            keyStore: InMemoryAIAPIKeyStore(),
            environment: ["OPENCODE_API_KEY": "bad"],
            homeDirectory: opencodeHome,
            now: { Date(timeIntervalSince1970: 1_786_493_600) }
        )
        let snapshot = await provider.fetchSnapshot()

        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.statusNote, "token expired — open OpenCode")
    }

    func testProviderFallsBackToLocalEstimateWithoutKey() async throws {
        let home = try makeTemporaryTestDirectory(testName: "OpenCodeGoLocalFallback")
        let now = Date(timeIntervalSince1970: 1_786_493_600)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        try Self.createLegacyDatabase(at: home.appendingPathComponent(".local/share/opencode/opencode.db"), rows: [
            (createdMs: nowMs - 3_600_000, cost: 6.0)
        ])

        let provider = OpenCodeGoUsageProvider(
            urlSession: makeMockedURLSession(),
            keyStore: InMemoryAIAPIKeyStore(),
            environment: [:],
            homeDirectory: home,
            now: { now }
        )
        let snapshot = await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 50)
        XCTAssertEqual(snapshot.statusNote, "local estimate — not account quota")
    }

    func testProviderUnavailableWithoutKeyOrLocal() async throws {
        let home = try makeTemporaryTestDirectory(testName: "OpenCodeGoUnavailable")
        let provider = OpenCodeGoUsageProvider(
            urlSession: makeMockedURLSession(),
            keyStore: InMemoryAIAPIKeyStore(),
            environment: [:],
            homeDirectory: home,
            now: { Date(timeIntervalSince1970: 1_786_493_600) }
        )
        let snapshot = await provider.fetchSnapshot()

        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.statusNote, "sign in to OpenCode Go")
    }

    // MARK: - Local aggregation

    func testLocalReaderAggregatesWindowsAgainstFixedLimits() throws {
        let home = try makeTemporaryTestDirectory(testName: "OpenCodeGoLocalWindows")
        let now = Date(timeIntervalSince1970: 1_786_493_600)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        try Self.createLegacyDatabase(at: home.appendingPathComponent(".local/share/opencode/opencode.db"), rows: [
            (createdMs: nowMs - 3_600_000, cost: 6.0)
        ])

        let snapshot = try XCTUnwrap(OpenCodeGoLocalUsage.snapshot(
            homeDirectory: home,
            environment: [:],
            now: now
        ))

        // $12/$30/$60 fixed denominators, same as CodexBar.
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 50)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 80)
        XCTAssertEqual(snapshot.tertiaryMonthlyWindow?.remainingPercent, 90)
        XCTAssertEqual(snapshot.statusNote, "local estimate — not account quota")
    }

    func testLocalReaderDedupsMigratedV2Messages() throws {
        let home = try makeTemporaryTestDirectory(testName: "OpenCodeGoLocalDedup")
        let now = Date(timeIntervalSince1970: 1_786_493_600)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let url = home.appendingPathComponent(".local/share/opencode/opencode.db")
        try Self.createLegacyDatabase(at: url, rows: [(createdMs: nowMs - 3_600_000, cost: 4.0)], messageID: "m1")
        try Self.insertSessionMessage(at: url, id: "m1", createdMs: nowMs - 3_600_000, cost: 4.0)

        let snapshot = try XCTUnwrap(OpenCodeGoLocalUsage.snapshot(
            homeDirectory: home,
            environment: [:],
            now: now
        ))

        // Counted once: 4/12 = 33.3% used -> 67% remaining, not 33%.
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 67)
    }

    func testLocalReaderIgnoresOtherProviders() throws {
        let home = try makeTemporaryTestDirectory(testName: "OpenCodeGoLocalOtherProvider")
        let now = Date(timeIntervalSince1970: 1_786_493_600)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let url = home.appendingPathComponent(".local/share/opencode/opencode.db")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE message (id TEXT PRIMARY KEY, data TEXT, time_created INTEGER)", nil, nil, nil), SQLITE_OK)
        let payload = "{\"time\":{\"created\":\(nowMs - 3_600_000)},\"cost\":6.0,\"providerID\":\"other\",\"role\":\"assistant\"}"
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO message (id, data, time_created) VALUES ('x', '\(payload)', \(nowMs - 3_600_000))", nil, nil, nil), SQLITE_OK)

        XCTAssertNil(OpenCodeGoLocalUsage.snapshot(homeDirectory: home, environment: [:], now: now))
    }

    // MARK: - Model compat

    func testSnapshotDecodesLegacyPayloadWithoutMonthly() throws {
        let json = """
        {"providerID":"codex","displayName":"Codex","sessionWindow":null,"weeklyWindow":null,
        "modelWindows":[],"isAvailable":false,"isStale":false,"fetchedAt":786493600}
        """
        let snapshot = try JSONDecoder().decode(UsageQuotaSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.tertiaryMonthlyWindow)
    }

    func testSnapshotRoundTripsMonthly() throws {
        let snapshot = UsageQuotaSnapshot(
            providerID: .opencodeGo,
            displayName: "OpenCode Go",
            sessionWindow: UsageWindow(remainingPercent: 80, resetAt: nil, label: "5h", durationSeconds: 18000),
            weeklyWindow: nil,
            tertiaryMonthlyWindow: UsageWindow(remainingPercent: 65, resetAt: nil, label: "30d", durationSeconds: 2_592_000),
            isAvailable: true
        )
        let restored = try JSONDecoder().decode(UsageQuotaSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored, snapshot)
    }

    // MARK: - Fixtures

    private struct LocalRow {
        let createdMs: Int64
        let cost: Double
    }

    private static func createLegacyDatabase(
        at url: URL,
        rows: [(createdMs: Int64, cost: Double)],
        messageID: String = "m1"
    ) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "OpenCodeGoUsageTests", code: 1)
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "CREATE TABLE message (id TEXT PRIMARY KEY, data TEXT, time_created INTEGER)", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "OpenCodeGoUsageTests", code: 2)
        }
        for (index, row) in rows.enumerated() {
            let id = rows.count == 1 ? messageID : "\(messageID)-\(index)"
            let payload = "{\"time\":{\"created\":\(row.createdMs)},\"cost\":\(row.cost),\"providerID\":\"opencode-go\",\"role\":\"assistant\"}"
            let escaped = payload.replacingOccurrences(of: "'", with: "''")
            let sql = "INSERT INTO message (id, data, time_created) VALUES ('\(id)', '\(escaped)', \(row.createdMs))"
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "OpenCodeGoUsageTests", code: 3)
            }
        }
    }

    private static func insertSessionMessage(at url: URL, id: String, createdMs: Int64, cost: Double) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "OpenCodeGoUsageTests", code: 4)
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(
            db,
            "CREATE TABLE IF NOT EXISTS session_message (id TEXT PRIMARY KEY, type TEXT, data TEXT, time_created INTEGER)",
            nil, nil, nil
        ) == SQLITE_OK else {
            throw NSError(domain: "OpenCodeGoUsageTests", code: 5)
        }
        let payload = "{\"time\":{\"created\":\(createdMs)},\"cost\":\(cost),\"model\":{\"providerID\":\"opencode-go\"}}"
        let escaped = payload.replacingOccurrences(of: "'", with: "''")
        let sql = "INSERT INTO session_message (id, type, data, time_created) VALUES ('\(id)', 'assistant', '\(escaped)', \(createdMs))"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "OpenCodeGoUsageTests", code: 6)
        }
    }
}

@MainActor
final class OpenCodeGoStoreTests: XCTestCase {
    func testStoreTogglesOpenCodeGoProvider() throws {
        let suiteName = "OpenCodeGoStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = UsageQuotaStore(defaults: defaults, providers: [])
        XCTAssertTrue(store.isProviderEnabled(.opencodeGo))
        store.setProviderEnabled(false, for: .opencodeGo)
        XCTAssertFalse(store.isProviderEnabled(.opencodeGo))
    }
}
