@testable import GitMenuBar
import XCTest

final class AntigravityUsageTests: XCTestCase {
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
            "groups": [
                {
                    "name": "Gemini Models",
                    "buckets": [
                        {
                            "modelId": "gemini-2.5-flash",
                            "remainingFraction": 0.75,
                            "resetTime": "2026-03-08T22:00:00Z"
                        }
                    ]
                },
                {
                    "name": "Claude and GPT",
                    "buckets": [
                        {
                            "modelId": "claude-3-7-sonnet",
                            "remainingFraction": 0.50,
                            "resetTime": "2026-03-12T00:00:00Z"
                        }
                    ]
                }
            ]
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let quotas = try AntigravityUsageParsing.parseQuotaSummaryResponse(data)

        XCTAssertEqual(quotas.count, 2)
        XCTAssertEqual(quotas[0].label, "Gemini Models")
        XCTAssertEqual(quotas[0].percentLeft, 75)
        XCTAssertEqual(quotas[1].label, "Claude and GPT")
        XCTAssertEqual(quotas[1].percentLeft, 50)
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
}
