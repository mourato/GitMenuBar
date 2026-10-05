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
            #"{"five_hour":{"utilization":23.5,"resets_at":1800003600},"seven_day":{"utilization":1.0,"resets_at":"2030-01-20T12:00:00Z"},"seven_day_sonnet":{"utilization":12,"resets_at":1800007200},"seven_day_opus":{"utilization":68,"resets_at":1800007200}}"#.utf8
        )

        let snapshot = try XCTUnwrap(ClaudeCodeUsageParsing.snapshot(fromUsageAPI: data, now: now))

        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 77)
        XCTAssertEqual(snapshot.sessionWindow?.intervalChip, "5h")
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 99)
        XCTAssertEqual(snapshot.weeklyWindow?.intervalChip, "7d")
        XCTAssertEqual(snapshot.modelWindows.map(\.label), ["Sonnet", "Opus"])
        XCTAssertEqual(snapshot.modelWindows.map(\.remainingPercent), [88, 32])
        XCTAssertEqual(snapshot.statusNote, "Claude Code OAuth usage API")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testParsesDynamicModelScopedUsageLimits() throws {
        let data = Data(
            #"{"five_hour":{"utilization":10},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":73,"resets_at":"2030-01-20T12:00:00Z","scope":{"model":{"id":"fable","display_name":"Fable"}}},{"kind":"weekly_scoped","group":"weekly","percent":99,"scope":{"model":{"display_name":"All models"}}}]}"#.utf8
        )

        let snapshot = try XCTUnwrap(ClaudeCodeUsageParsing.snapshot(fromUsageAPI: data))

        XCTAssertEqual(snapshot.modelWindows.map(\.label), ["Fable only"])
        XCTAssertEqual(snapshot.modelWindows.first?.remainingPercent, 27)
    }

    func testParsesCLIUsagePanel() throws {
        let output = """
        Settings: Usage
        Current session
        25% used
        Current week (all models)
        40% used
        Current week (Sonnet only)
        12% used
        """

        let snapshot = try XCTUnwrap(
            ClaudeCodeCLIUsage.snapshot(
                from: output,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 75)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 60)
        XCTAssertEqual(snapshot.modelWindows.map(\.label), ["Sonnet only"])
        XCTAssertEqual(snapshot.modelWindows.first?.remainingPercent, 88)
        XCTAssertEqual(snapshot.statusNote, "Claude Code CLI PTY /usage")
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
                Data(#"{"five_hour":{"utilization":25,"resets_at":1800003600}}"#.utf8)
            )
        }

        let provider = ClaudeCodeUsageProvider(
            homeDirectory: root,
            credentialsURL: credentialsURL,
            session: makeMockedURLSession(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            keychainData: { nil },
            cookieSessionKey: { nil },
            cliSnapshot: { nil }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 75)
        XCTAssertEqual(authorization.value, "Bearer access-token")
        XCTAssertEqual(beta.value, "oauth-2025-04-20")
        XCTAssertEqual(requests.values, ["/api/oauth/usage"])
    }

    func testUsageProviderRefreshesExpiredOAuthCredentials() async throws {
        let root = try makeTemporaryTestDirectory(testName: #function)
        let credentialsURL = root.appendingPathComponent(".credentials.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try #"{"claudeAiOauth":{"accessToken":"expired-access","refreshToken":"refresh-token","expiresAt":1799999000000}}"#.write(
            to: credentialsURL,
            atomically: true,
            encoding: .utf8
        )

        let paths = PromptListCapture()
        let refreshedAuthorization = PromptCapture()
        let refreshBody = PromptCapture()
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            paths.append(path)
            if path == "/v1/oauth/token" {
                refreshBody.set(String(data: requestBodyData(from: request), encoding: .utf8) ?? "")
                return try (
                    makeMockHTTPResponse(for: request),
                    Data(#"{"access_token":"fresh-access","refresh_token":"rotated-refresh","expires_in":3600}"#.utf8)
                )
            }

            refreshedAuthorization.set(request.value(forHTTPHeaderField: "Authorization") ?? "")
            return try (
                makeMockHTTPResponse(for: request),
                Data(#"{"five_hour":{"utilization":25,"resets_at":1800003600}}"#.utf8)
            )
        }

        let provider = ClaudeCodeUsageProvider(
            homeDirectory: root,
            credentialsURL: credentialsURL,
            session: makeMockedURLSession(),
            now: { now },
            keychainData: { nil }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 75)
        XCTAssertEqual(paths.values, ["/v1/oauth/token", "/api/oauth/usage"])
        XCTAssertEqual(refreshedAuthorization.value, "Bearer fresh-access")
        XCTAssertTrue(refreshBody.value.contains("grant_type=refresh_token"))
        XCTAssertTrue(refreshBody.value.contains("refresh_token=refresh-token"))
        XCTAssertTrue(refreshBody.value.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))

        let persisted = try Data(contentsOf: credentialsURL)
        let rootObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        let oauth = try XCTUnwrap(rootObject["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["accessToken"] as? String, "fresh-access")
        XCTAssertEqual(oauth["refreshToken"] as? String, "rotated-refresh")
        XCTAssertEqual(oauth["expiresAt"] as? Double, 1_800_003_600_000)
    }

    func testUsageProviderFallsBackToBrowserCookies() async throws {
        let root = try makeTemporaryTestDirectory(testName: #function)
        let paths = PromptListCapture()
        let cookie = PromptCapture()
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url?.path ?? "")
            cookie.set(request.value(forHTTPHeaderField: "Cookie") ?? "")
            let body = request.url?.path == "/api/organizations"
                ? #"[{"uuid":"organization-id"}]"#
                : #"{"five_hour":{"utilization":25,"resets_at":1800003600},"seven_day_sonnet":{"utilization":10}}"#
            return try (makeMockHTTPResponse(for: request), Data(body.utf8))
        }

        let provider = ClaudeCodeUsageProvider(
            homeDirectory: root,
            credentialsURL: root.appendingPathComponent(".credentials.json"),
            session: makeMockedURLSession(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            keychainData: { nil },
            cookieSessionKey: { "sk-ant-browser-session" }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 75)
        XCTAssertEqual(snapshot.modelWindows.first?.label, "Sonnet")
        XCTAssertEqual(snapshot.statusNote, "Claude Code browser cookie usage API")
        XCTAssertEqual(paths.values, ["/api/organizations", "/api/organizations/organization-id/usage"])
        XCTAssertEqual(cookie.value, "sessionKey=sk-ant-browser-session")
    }

    func testUsageProviderFallsBackToCLIUsage() async throws {
        let root = try makeTemporaryTestDirectory(testName: #function)
        let cliSnapshot = UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: UsageProviderID.claudeCode.displayName,
            sessionWindow: UsageWindow(
                remainingPercent: 64,
                resetAt: nil,
                label: "5h",
                durationSeconds: 5 * 3600
            ),
            weeklyWindow: nil,
            isAvailable: true,
            statusNote: "Claude Code CLI PTY /usage",
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let provider = ClaudeCodeUsageProvider(
            homeDirectory: root,
            credentialsURL: root.appendingPathComponent(".credentials.json"),
            session: makeMockedURLSession(),
            keychainData: { nil },
            cookieSessionKey: { nil },
            cliSnapshot: { cliSnapshot }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertEqual(snapshot, cliSnapshot)
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
            keychainData: { nil },
            cookieSessionKey: { nil },
            cliSnapshot: { nil }
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
            keychainData: { nil },
            cookieSessionKey: { nil },
            cliSnapshot: { nil }
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

    @MainActor
    func testMenuBarGroupsIncludeModelWindows() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TestGroupsModels-\(UUID().uuidString)"))
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        let snapshot = UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            sessionWindow: UsageWindow(
                remainingPercent: 77,
                resetAt: nil,
                label: "5h",
                durationSeconds: 5 * 3600
            ),
            weeklyWindow: UsageWindow(
                remainingPercent: 58,
                resetAt: nil,
                label: "7d",
                durationSeconds: 7 * 86400
            ),
            modelWindows: [
                UsageWindow(remainingPercent: 88, resetAt: nil, label: "Sonnet", durationSeconds: 7 * 86400),
                UsageWindow(remainingPercent: 32, resetAt: nil, label: "Opus", durationSeconds: 7 * 86400)
            ],
            isAvailable: true
        )

        let groups = UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.values, ["77%", "58%", "Sonnet 88%", "Opus 32%"])
        XCTAssertEqual(groups.first?.fractions.count, 4)
    }

    @MainActor
    func testMenuBarGroupsRespectMarkOnlySelection() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TestGroupsMarkOnly-\(UUID().uuidString)"))
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.setSelectedMetrics([], for: .claudeCode)
        let snapshot = UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            sessionWindow: UsageWindow(
                remainingPercent: 77,
                resetAt: nil,
                label: "5h",
                durationSeconds: 5 * 3600
            ),
            weeklyWindow: nil,
            modelWindows: [
                UsageWindow(remainingPercent: 88, resetAt: nil, label: "Sonnet", durationSeconds: 7 * 86400)
            ],
            isAvailable: true
        )

        let groups = UsageQuotaMenuPresentation.groups(snapshots: [snapshot], preferences: preferences)

        XCTAssertTrue(groups.isEmpty)
    }
}
