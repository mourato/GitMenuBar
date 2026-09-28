@testable import GitMenuBar
import XCTest

final class ClaudeCodeUsageTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testParsesUsageAPIWindows() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let data = Data(
            #"{"five_hour":{"utilization":23.5,"resets_at":1800003600},"seven_day":{"utilization":0.42,"resets_at":"2030-01-20T12:00:00Z"}}"#.utf8
        )

        let snapshot = try XCTUnwrap(ClaudeCodeUsageParsing.snapshot(fromUsageAPI: data, now: now))

        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 77)
        XCTAssertEqual(snapshot.sessionWindow?.intervalChip, "5h")
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 58)
        XCTAssertEqual(snapshot.weeklyWindow?.intervalChip, "7d")
        XCTAssertEqual(snapshot.statusNote, "Claude Code OAuth usage API")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testReadsAccessTokenFromClaudeCredentials() {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"access-token"}}"#.utf8)

        XCTAssertEqual(ClaudeCodeUsageParsing.accessToken(fromCredentials: data), "access-token")
        XCTAssertNil(ClaudeCodeUsageParsing.accessToken(fromCredentials: Data(#"{"claudeAiOauth":{}}"#.utf8)))
    }

    func testUsageProviderUsesExistingOAuthCredentials() async throws {
        let root = try makeTemporaryTestDirectory(testName: #function)
        let credentialsURL = root.appendingPathComponent(".credentials.json")
        try #"{"claudeAiOauth":{"accessToken":"access-token"}}"#.write(
            to: credentialsURL,
            atomically: true,
            encoding: .utf8
        )

        let requests = PromptListCapture()
        let authorization = PromptCapture()
        let beta = PromptCapture()
        MockURLProtocol.requestHandler = { request in
            requests.append(request.url?.path ?? "")
            authorization.set(request.value(forHTTPHeaderField: "Authorization") ?? "")
            beta.set(request.value(forHTTPHeaderField: "anthropic-beta") ?? "")
            return try (
                makeMockHTTPResponse(for: request),
                Data(#"{"five_hour":{"utilization":0.25,"resets_at":1800003600}}"#.utf8)
            )
        }

        let provider = ClaudeCodeUsageProvider(
            homeDirectory: root,
            credentialsURL: credentialsURL,
            session: makeMockedURLSession(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            keychainData: { nil }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 75)
        XCTAssertEqual(authorization.value, "Bearer access-token")
        XCTAssertEqual(beta.value, "oauth-2025-04-20")
        XCTAssertEqual(requests.values, ["/api/oauth/usage"])
    }

    func testUsageProviderFallsBackToLocalEventsWhenUsageAPIFails() async throws {
        let root = try makeTemporaryTestDirectory(testName: #function)
        let credentialsURL = root.appendingPathComponent(".credentials.json")
        let projectDirectory = root.appendingPathComponent(".claude/projects/example", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try #"{"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.5,"resetsAt":1800003600}}"#.write(
            to: projectDirectory.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"claudeAiOauth":{"accessToken":"access-token"}}"#.write(
            to: credentialsURL,
            atomically: true,
            encoding: .utf8
        )

        MockURLProtocol.requestHandler = { request in
            let requestURL = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: requestURL,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, Data())
        }

        let provider = ClaudeCodeUsageProvider(
            homeDirectory: root,
            credentialsURL: credentialsURL,
            session: makeMockedURLSession(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            keychainData: { nil }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 50)
        XCTAssertEqual(snapshot.statusNote, "Claude Code local rate limit events")
    }

    func testUsageProviderReturnsUnavailableWithoutCredentials() async throws {
        let root = try makeTemporaryTestDirectory(testName: #function)
        let provider = ClaudeCodeUsageProvider(
            homeDirectory: root,
            credentialsURL: root.appendingPathComponent(".credentials.json"),
            session: makeMockedURLSession(),
            keychainData: { nil }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.statusNote, "sign in to Claude Code")
    }

    func testParsesLatestFiveHourAndSevenDayEvents() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let text = """
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.25,"resetsAt":1800003600}}
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"seven_day","utilization":42,"resetsAt":"2030-01-20T12:00:00Z"}}
        """

        let snapshot = try XCTUnwrap(ClaudeCodeUsageParsing.snapshot(fromJSONL: text, now: now))

        XCTAssertEqual(snapshot.providerID, .claudeCode)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 75)
        XCTAssertEqual(snapshot.sessionWindow?.intervalChip, "5h")
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 58)
        XCTAssertEqual(snapshot.weeklyWindow?.intervalChip, "7d")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testKeepsNewestReadingForEachWindow() throws {
        let text = """
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.80,"resetsAt":1800001000}}
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.20,"resetsAt":1800002000}}
        """

        let snapshot = try XCTUnwrap(ClaudeCodeUsageParsing.snapshot(fromJSONL: text))
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 80)
        XCTAssertEqual(snapshot.sessionWindow?.resetAt, Date(timeIntervalSince1970: 1_800_002_000))
    }

    func testIgnoresEventsWithoutUtilization() {
        let text = """
        {"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","resetsAt":1800003600}}
        """

        XCTAssertNil(ClaudeCodeUsageParsing.snapshot(fromJSONL: text))
    }
}
