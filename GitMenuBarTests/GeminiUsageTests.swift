@testable import GitMenuBar
import XCTest

final class GeminiUsageTests: XCTestCase {
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
}
