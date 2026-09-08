@testable import GitMenuBar
import XCTest

final class AntigravityUsageTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testParseUserStatusResponseExtractsModelConfigs() throws {
        let json = """
        {
            "userStatus": {
                "email": "dev@example.com",
                "cascadeModelConfigData": {
                    "clientModelConfigs": [
                        {
                            "label": "Gemini 2.5 Flash",
                            "modelOrAlias": { "model": "gemini-2.5-flash" },
                            "quotaInfo": {
                                "remainingFraction": 0.85,
                                "resetTime": "2026-03-08T22:00:00Z"
                            }
                        },
                        {
                            "label": "Claude 3.7 Sonnet",
                            "modelOrAlias": { "model": "claude-3-7-sonnet" },
                            "quotaInfo": {
                                "remainingFraction": 0.60,
                                "resetTime": "2026-03-12T00:00:00Z"
                            }
                        }
                    ]
                }
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let quotas = try AntigravityUsageParsing.parseUserStatusResponse(data)

        XCTAssertEqual(quotas.count, 2)
        XCTAssertEqual(quotas[0].label, "Gemini 2.5 Flash")
        XCTAssertEqual(quotas[0].percentLeft, 85)
        XCTAssertEqual(quotas[1].label, "Claude 3.7 Sonnet")
        XCTAssertEqual(quotas[1].percentLeft, 60)
    }

    func testParseQuotaSummaryResponseExtractsBuckets() throws {
        let json = """
        {
            "response": {
                "description": "Within each group, models share a weekly limit and a 5-hour limit.",
                "groups": [
                {
                    "displayName": "Gemini Models",
                    "buckets": [
                        {
                            "bucketId": "gemini-weekly",
                            "displayName": "Weekly Limit",
                            "remaining": { "remainingFraction": 0.75 },
                            "resetTime": "2026-03-08T22:00:00Z"
                        }
                    ]
                },
                {
                    "displayName": "Claude and GPT models",
                    "buckets": [
                        {
                            "bucketId": "3p-5h",
                            "displayName": "Five Hour Limit",
                            "remaining": { "case": "remainingFraction", "value": 0.50 },
                            "resetTime": "2026-03-12T00:00:00Z"
                        }
                    ]
                }
                ]
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let quotas = try AntigravityUsageParsing.parseQuotaSummaryResponse(data)

        XCTAssertEqual(quotas.count, 2)
        XCTAssertEqual(quotas[0].modelId, "gemini-weekly")
        XCTAssertEqual(quotas[0].label, "Weekly Limit")
        XCTAssertEqual(quotas[0].percentLeft, 75)
        XCTAssertEqual(quotas[1].modelId, "3p-5h")
        XCTAssertEqual(quotas[1].label, "Five Hour Limit")
        XCTAssertEqual(quotas[1].percentLeft, 50)
    }

    func testParseCommandModelConfigResponseExtractsLegacyBuckets() throws {
        let json = """
        {
            "clientModelConfigs": [
                {
                    "label": "Gemini 3 Pro Low",
                    "modelOrAlias": { "model": "gemini-3-pro-low" },
                    "quotaInfo": { "remainingFraction": 0.90 }
                }
            ]
        }
        """

        let quotas = try AntigravityUsageParsing.parseCommandModelConfigResponse(Data(json.utf8))

        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(quotas[0].modelId, "gemini-3-pro-low")
        XCTAssertEqual(quotas[0].percentLeft, 90)
    }

    func testAntigravitySnapshotUsesRealFiveHourAndWeeklyBuckets() throws {
        let json = """
        {
          "response": {
            "groups": [
              {
                "displayName": "Gemini Models",
                "buckets": [
                  { "bucketId": "gemini-weekly", "displayName": "Weekly Limit", "remaining": { "remainingFraction": 0.82 } },
                  { "bucketId": "gemini-5h", "displayName": "Five Hour Limit", "remaining": { "remainingFraction": 0.91 } }
                ]
              },
              {
                "displayName": "Claude and GPT models",
                "buckets": [
                  { "bucketId": "3p-weekly", "displayName": "Weekly Limit", "remaining": { "remainingFraction": 0.64 } },
                  { "bucketId": "3p-5h", "displayName": "Five Hour Limit", "remaining": { "remainingFraction": 0.73 } }
                ]
              }
            ]
          }
        }
        """

        let quotas = try AntigravityUsageParsing.parseQuotaSummaryResponse(Data(json.utf8))
        let snapshot = AntigravityUsageParsing.snapshot(from: quotas)

        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 73)
        XCTAssertEqual(snapshot.sessionWindow?.durationSeconds, 18000)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 64)
        XCTAssertEqual(snapshot.weeklyWindow?.durationSeconds, 604_800)
    }

    func testAntigravitySnapshotMapsGeminiAndClaudeGptWindows() {
        let geminiQuota = AntigravityUsageParsing.ModelQuota(
            label: "Gemini 2.5 Flash",
            modelId: "gemini-2.5-flash",
            remainingFraction: 0.70,
            resetAt: Date().addingTimeInterval(3600)
        )
        let claudeQuota = AntigravityUsageParsing.ModelQuota(
            label: "Claude 3.7 Sonnet",
            modelId: "claude-3-7-sonnet",
            remainingFraction: 0.45,
            resetAt: Date().addingTimeInterval(86400 * 3)
        )

        let snapshot = AntigravityUsageParsing.snapshot(from: [geminiQuota, claudeQuota])

        XCTAssertEqual(snapshot.providerID, .antigravity)
        XCTAssertEqual(snapshot.displayName, "Antigravity")
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 70)
        XCTAssertEqual(snapshot.sessionWindow?.label, "Gemini")
        XCTAssertEqual(snapshot.sessionWindow?.durationSeconds, 18000)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 45)
        XCTAssertEqual(snapshot.weeklyWindow?.label, "Claude/GPT")
        XCTAssertEqual(snapshot.weeklyWindow?.durationSeconds, 604_800)
    }

    func testAntigravityCSRFTokenExtraction() {
        let cmd1 = "/path/to/language_server --csrf_token secret-token-123 --port 1234"
        XCTAssertEqual(AntigravityProcessDetector.extractCSRFToken(from: cmd1), "secret-token-123")

        let cmd2 = "/path/to/language_server --csrf-token=another_token_456"
        XCTAssertEqual(AntigravityProcessDetector.extractCSRFToken(from: cmd2), "another_token_456")

        let cmd3 = "/path/to/language_server without token"
        XCTAssertNil(AntigravityProcessDetector.extractCSRFToken(from: cmd3))

        XCTAssertEqual(
            AntigravityProcessDetector.extractPort(
                "--extension_server_port",
                from: "--extension_server_port=4321"
            ),
            4321
        )
        XCTAssertEqual(
            AntigravityProcessDetector.extractFlag(
                "--extension_server_csrf_token",
                from: "--extension_server_csrf_token extension-token"
            ),
            "extension-token"
        )
    }

    func testAntigravityCandidatePathDetection() {
        XCTAssertTrue(AntigravityProcessDetector.isAntigravityCandidatePath("/Applications/Antigravity.app/Contents/MacOS/Antigravity"))
        XCTAssertTrue(AntigravityProcessDetector.isAntigravityCandidatePath("/Users/user/.gemini/antigravity/bin/agy"))
        XCTAssertTrue(AntigravityProcessDetector.isAntigravityCandidatePath("/path/to/language_server_macos_arm"))
        XCTAssertFalse(AntigravityProcessDetector.isAntigravityCandidatePath("/usr/bin/git"))
    }

    func testAntigravityUsageProviderReturnsUnavailableWhenNoServersAndNoRemoteCreds() async {
        let provider = AntigravityUsageProvider(
            configuration: AntigravityUsageProvider.Configuration(
                remoteCredentialsURL: URL(fileURLWithPath: "/tmp/non_existent_antigravity_creds.json")
            ),
            processDetector: { [] }
        )

        let snapshot = await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.providerID, .antigravity)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.statusNote, "sign in to Antigravity")
    }

    func testAntigravityUsageProviderUsesHTTPSQuotaSummaryBeforeLegacyEndpoint() async {
        let paths = PromptListCapture()
        let bodies = PromptListCapture()
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url?.absoluteString ?? "")
            bodies.append(String(data: requestBodyData(from: request), encoding: .utf8) ?? "")

            if request.url?.path.contains("RetrieveUserQuotaSummary") == true {
                return try (
                    makeMockHTTPResponse(for: request),
                    Data(#"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-5h","displayName":"Five Hour Limit","remaining":{"remainingFraction":0.88}}]}]}}"#.utf8)
                )
            }

            return try (
                XCTUnwrap(try HTTPURLResponse(
                    url: XCTUnwrap(request.url),
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )),
                Data()
            )
        }

        let provider = AntigravityUsageProvider(
            session: makeMockedURLSession(),
            processDetector: {
                [AntigravityProcessDetector.DetectedServer(
                    pid: 42,
                    port: 4321,
                    csrfToken: "csrf-token"
                )]
            }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 88)
        XCTAssertEqual(paths.values.count, 1)
        XCTAssertTrue(paths.values[0].hasPrefix("https://127.0.0.1:4321/"))
        XCTAssertEqual(bodies.values, [#"{"forceRefresh":true}"#])
    }
}
