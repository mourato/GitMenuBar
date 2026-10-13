@testable import GitMenuBar
import XCTest

final class UsageQuotaCostEstimateTests: XCTestCase {
    func testCodexCostSplitsCachedSubset() {
        // gpt-5.6-luna: input 2e-7, cached-read 2e-8, output 1.2e-6.
        let cost = UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 21330,
            cachedInputTokens: 6912,
            outputTokens: 480
        )
        let expected = Double(21330 - 6912) * 2e-7 + Double(6912) * 2e-8 + Double(480) * 1.2e-6
        XCTAssertEqual(cost ?? -1, expected, accuracy: 1e-9)
    }

    func testCodexCostUnknownModelIsNil() {
        XCTAssertNil(UsageQuotaAPIPricing.codexCostUSD(
            model: "not-a-model",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 10
        ))
    }

    func testCodexModelNormalization() throws {
        // gpt-reserve aliases gpt-5.6-luna: input 2e-7, output 1.2e-6.
        let reserve = UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-reserve",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 10
        )
        XCTAssertEqual(reserve ?? -1, Double(100) * 2e-7 + Double(10) * 1.2e-6, accuracy: 1e-9)

        // A dated snapshot must price like its base model.
        let base = try XCTUnwrap(UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-5.2",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 10
        ))
        let dated = UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-5.2-2025-01-01",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 10
        )
        XCTAssertEqual(dated ?? -1, base, accuracy: 1e-9)
    }

    func testClaudeCostSplitsHourlyCacheCreation() {
        // claude-haiku-5-5: input 1e-7, output 5e-7, read 1e-8, 5m-create 1.25e-7, 1h-create at 2x input.
        let cost = UsageQuotaAPIPricing.claudeCostUSD(
            model: "claude-haiku-5-5",
            inputTokens: 2,
            cacheReadInputTokens: 70388,
            cacheCreationInputTokens: 31219,
            cacheCreationInputTokens1h: 31219,
            outputTokens: 1131
        )
        let expected = Double(2) * 1e-7 + Double(70388) * 1e-8
            + Double(31219) * 1e-7 * 2 + Double(1131) * 5e-7
        XCTAssertEqual(cost ?? -1, expected, accuracy: 1e-9)
    }

    func testClaudeCostUnknownModelIsNil() {
        XCTAssertNil(UsageQuotaAPIPricing.claudeCostUSD(
            model: "claude-future-9",
            inputTokens: 100,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 10
        ))
    }

    func testEstimateFromFixtures() throws {
        let home = try makeTemporaryTestDirectory(testName: "CostEstimate")
        let now = Date()
        let monthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        ) ?? now
        let timestamp = ISO8601DateFormatter().string(from: monthStart.addingTimeInterval(3600))

        let codexDir = home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let codexLines = [
            #"{"timestamp":"\#(timestamp)","ordinal":1,"type":"turn_context","payload":{"turn_id":"t1","model":"gpt-5.6-luna"}}"#,
            #"{"timestamp":"\#(timestamp)","ordinal":2,"type":"token_usage_record","payload":{"turn_id":"t1","turn_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"cache_write_input_tokens":0,"output_tokens":100}}}"#,
            #"{"timestamp":"\#(timestamp)","ordinal":3,"type":"token_usage_record","payload":{"turn_id":"t1","turn_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"cache_write_input_tokens":0,"output_tokens":100}}}"#
        ]
        try codexLines.joined(separator: "\n").write(
            to: codexDir.appendingPathComponent("rollout-test.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let claudeDir = home.appendingPathComponent(".claude/projects/proj", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let claudeRecord = #"{"requestId":"r1","uuid":"u1","timestamp":"\#(timestamp)","message":{"role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":20}}}"#
        let claudeDup = #"{"requestId":"r1","uuid":"u2","timestamp":"\#(timestamp)","message":{"role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":20}}}"#
        try [claudeRecord, claudeDup].joined(separator: "\n").write(
            to: claudeDir.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let estimate = UsageQuotaCostScanner.estimate(homeDirectory: home, now: now)
        XCTAssertEqual(estimate.rows.count, 2)

        let openAI = try XCTUnwrap(estimate.rows.first { $0.title == "OpenAI API" })
        // Duplicate turn_id counted once: (1000-200) * 2e-7 + 200 * 2e-8 + 100 * 1.2e-6.
        let expectedCodex = Double(800) * 2e-7 + Double(200) * 2e-8 + Double(100) * 1.2e-6
        XCTAssertEqual(openAI.amountUSD ?? -1, expectedCodex, accuracy: 1e-9)

        let anthropic = try XCTUnwrap(estimate.rows.first { $0.title == "Anthropic API" })
        // Duplicate requestId counted once: 10 * 1e-7 + 20 * 5e-7.
        let expectedClaude = Double(10) * 1e-7 + Double(20) * 5e-7
        XCTAssertEqual(anthropic.amountUSD ?? -1, expectedClaude, accuracy: 1e-12)
    }

    func testEstimateSkipsStaleFilesAndIsStableOnRescan() throws {
        let home = try makeTemporaryTestDirectory(testName: "CostEstimateStale")
        let now = Date()
        let monthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        ) ?? now
        let timestamp = ISO8601DateFormatter().string(from: monthStart.addingTimeInterval(3600))

        let claudeDir = home.appendingPathComponent(".claude/projects/proj", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let claudeRecord = #"{"requestId":"r1","uuid":"u1","timestamp":"\#(timestamp)","message":{"role":"assistant","model":"claude-haiku-5-5","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":20}}}"#
        let file = claudeDir.appendingPathComponent("session.jsonl")
        try claudeRecord.write(to: file, atomically: true, encoding: .utf8)

        // Modified before this month: must be skipped without being read.
        try FileManager.default.setAttributes(
            [.modificationDate: monthStart.addingTimeInterval(-86400)],
            ofItemAtPath: file.path
        )
        XCTAssertTrue(UsageQuotaCostScanner.estimate(homeDirectory: home, now: now).rows.isEmpty)

        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        let first = UsageQuotaCostScanner.estimate(homeDirectory: home, now: now)
        let second = UsageQuotaCostScanner.estimate(homeDirectory: home, now: now)
        XCTAssertEqual(first.rows.count, 1)
        XCTAssertEqual(first, second)
    }

    func testEstimateEmptyHomeHasNoRows() throws {
        let home = try makeTemporaryTestDirectory(testName: "CostEstimateEmpty")
        XCTAssertTrue(UsageQuotaCostScanner.estimate(homeDirectory: home).rows.isEmpty)
    }
}
