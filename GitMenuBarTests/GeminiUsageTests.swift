@testable import GitMenuBar
import XCTest

final class GeminiUsageTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testParseAPIResponseExtractsBucketsAndGroupsByModel() throws {
        let json = """
        {
            "buckets": [
                {
                    "modelId": "gemini-2.5-pro",
                    "remainingFraction": 0.85,
                    "resetTime": "2026-03-08T18:00:00Z"
                },
                {
                    "modelId": "gemini-2.5-pro",
                    "remainingFraction": 0.70,
                    "resetTime": "2026-03-08T18:00:00Z"
                },
                {
                    "modelId": "gemini-2.5-flash",
                    "remainingFraction": 0.95,
                    "resetTime": "2026-03-08T20:00:00.000Z"
                }
            ]
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let quotas = try GeminiUsageParsing.parseAPIResponse(data)

        XCTAssertEqual(quotas.count, 2)
        // Check gemini-2.5-pro picked lowest remaining fraction (0.70 -> 70%)
        let proQuota = try XCTUnwrap(quotas.first { $0.modelId == "gemini-2.5-pro" })
        XCTAssertEqual(proQuota.percentLeft, 70)
        XCTAssertNotNil(proQuota.resetAt)

        // Check gemini-2.5-flash
        let flashQuota = try XCTUnwrap(quotas.first { $0.modelId == "gemini-2.5-flash" })
        XCTAssertEqual(flashQuota.percentLeft, 95)
        XCTAssertNotNil(flashQuota.resetAt)
    }

    func testGeminiSnapshotCreatesSessionAndWeeklyWindows() {
        let proQuota = GeminiUsageParsing.ModelQuota(
            modelId: "gemini-2.5-pro",
            percentLeft: 65,
            resetAt: Date().addingTimeInterval(3600)
        )
        let flashQuota = GeminiUsageParsing.ModelQuota(
            modelId: "gemini-2.5-flash",
            percentLeft: 90,
            resetAt: Date().addingTimeInterval(7200)
        )

        let snapshot = GeminiUsageParsing.snapshot(from: [proQuota, flashQuota])

        XCTAssertEqual(snapshot.providerID, .gemini)
        XCTAssertEqual(snapshot.displayName, "Gemini")
        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 65)
        XCTAssertEqual(snapshot.sessionWindow?.label, "Pro")
        XCTAssertEqual(snapshot.sessionWindow?.durationSeconds, 86400)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 90)
        XCTAssertEqual(snapshot.weeklyWindow?.label, "Flash")
        XCTAssertEqual(snapshot.weeklyWindow?.durationSeconds, 86400)
    }

    func testGeminiSnapshotReturnsUnavailableWhenQuotasEmpty() {
        let snapshot = GeminiUsageParsing.snapshot(from: [])
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.providerID, .gemini)
    }

    func testGeminiUsageProviderReturnsUnavailableWhenCredentialsFileMissing() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let nonExistentFile = tempDir.appendingPathComponent("non_existent_creds.json")

        let provider = GeminiUsageProvider(
            configuration: GeminiUsageProvider.Configuration(credentialsURL: nonExistentFile)
        )
        let snapshot = await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .gemini)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.statusNote, "sign in to Gemini CLI")
    }

    func testGeminiUsageProviderReturnsUnavailableWhenCredentialsCorrupt() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let credsURL = tempDir.appendingPathComponent("oauth_creds.json")
        try "invalid json".write(to: credsURL, atomically: true, encoding: .utf8)

        let provider = GeminiUsageProvider(
            configuration: GeminiUsageProvider.Configuration(credentialsURL: credsURL)
        )
        let snapshot = await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.providerID, .gemini)
        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.statusNote, "invalid Gemini credentials")
    }

    func testGeminiUsageProviderUsesCLIProjectAndQuotaEndpoint() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let credentialsURL = tempDir.appendingPathComponent("oauth_creds.json")
        let credentials = #"{"access_token":"access-token","expiry_date":4102444800000}"#
        try credentials.write(to: credentialsURL, atomically: true, encoding: .utf8)

        let paths = PromptListCapture()
        let bodies = PromptListCapture()
        MockURLProtocol.requestHandler = { request in
            paths.append(request.url?.path ?? "")
            bodies.append(String(data: requestBodyData(from: request), encoding: .utf8) ?? "")

            switch request.url?.path {
            case "/v1internal:loadCodeAssist":
                return try (
                    makeMockHTTPResponse(for: request),
                    Data(#"{"cloudaicompanionProject":{"id":"gen-lang-client-project"}}"#.utf8)
                )
            case "/v1internal:retrieveUserQuota":
                return try (
                    makeMockHTTPResponse(for: request),
                    Data(#"{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":0.72,"resetTime":"2026-03-08T18:00:00Z"}]}"#.utf8)
                )
            default:
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
        }

        let provider = GeminiUsageProvider(
            configuration: GeminiUsageProvider.Configuration(credentialsURL: credentialsURL),
            session: makeMockedURLSession(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let snapshot = await provider.fetchSnapshot()

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.sessionWindow?.remainingPercent, 72)
        XCTAssertEqual(paths.values, [
            "/v1internal:loadCodeAssist",
            "/v1internal:retrieveUserQuota"
        ])

        let loadBody = try XCTUnwrap(bodies.values.first.flatMap { $0.data(using: .utf8) })
        let loadJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: loadBody) as? [String: Any])
        let metadata = try XCTUnwrap(loadJSON["metadata"] as? [String: String])
        XCTAssertEqual(metadata["ideType"], "GEMINI_CLI")
        XCTAssertEqual(metadata["pluginType"], "GEMINI")

        let quotaBody = try XCTUnwrap(bodies.values.last.flatMap { $0.data(using: .utf8) })
        let quotaJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: quotaBody) as? [String: String])
        XCTAssertEqual(quotaJSON["project"], "gen-lang-client-project")
    }
}
