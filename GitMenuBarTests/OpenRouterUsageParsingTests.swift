@testable import GitMenuBar
import XCTest

final class OpenRouterUsageParsingTests: XCTestCase {
    private func data(forCredits totalCredits: Double, usage totalUsage: Double) -> Data {
        let json = """
        {"data":{"total_credits":\(totalCredits),"total_usage":\(totalUsage)}}
        """
        return Data(json.utf8)
    }

    func testSnapshotFromCreditsData() {
        let state = OpenRouterUsageState(totalCredits: 10, totalUsage: 0, quotaBaseCredits: 10, usageAtQuotaBase: 0)
        let snapshot = OpenRouterUsageParsing.parse(
            fromCreditsData: data(forCredits: 10, usage: 4),
            previousState: state
        )?.snapshot

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 60)
        XCTAssertNil(snapshot?.sessionWindow?.resetAt)
        XCTAssertEqual(snapshot?.sessionWindow?.intervalChip, "Credits")
        XCTAssertEqual(snapshot?.creditValueText, "$6.00 left")
        XCTAssertEqual(snapshot?.statusNote, "openrouter credits api")
        XCTAssertTrue(snapshot?.isAvailable ?? false)
        XCTAssertEqual(snapshot?.providerID, .openrouter)
    }

    func testMissingBaselineUsesCurrentBalanceAsFallback() throws {
        let parsed = try XCTUnwrap(OpenRouterUsageParsing.parse(
            fromCreditsData: data(forCredits: 100, usage: 91.18)
        ))

        XCTAssertEqual(parsed.state.quotaBaseCredits, 8.82, accuracy: 0.0001)
        XCTAssertEqual(parsed.state.usageAtQuotaBase, 91.18, accuracy: 0.0001)
        XCTAssertEqual(parsed.snapshot.sessionWindow?.remainingPercent, 100)
        XCTAssertEqual(parsed.snapshot.creditValueText, "$8.82 left")

        let afterTopUp = try XCTUnwrap(OpenRouterUsageParsing.parse(
            fromCreditsData: data(forCredits: 110, usage: 92.18),
            previousState: parsed.state
        ))

        XCTAssertEqual(afterTopUp.state.quotaBaseCredits, 18.82, accuracy: 0.0001)
        XCTAssertEqual(afterTopUp.snapshot.sessionWindow?.remainingPercent, 95)
        XCTAssertEqual(afterTopUp.snapshot.creditValueText, "$17.82 left")
    }

    func testTopUpPreservesBalanceFromBeforeTopUp() throws {
        let previous = OpenRouterUsageState(
            totalCredits: 10,
            totalUsage: 9.82,
            quotaBaseCredits: 10,
            usageAtQuotaBase: 0
        )
        let parsed = try XCTUnwrap(OpenRouterUsageParsing.parse(
            fromCreditsData: data(forCredits: 20, usage: 10.82),
            previousState: previous
        ))

        XCTAssertEqual(parsed.state.quotaBaseCredits, 10.18, accuracy: 0.0001)
        XCTAssertEqual(parsed.state.usageAtQuotaBase, 9.82, accuracy: 0.0001)
        XCTAssertEqual(parsed.snapshot.sessionWindow?.remainingPercent, 90)
        XCTAssertEqual(parsed.snapshot.creditValueText, "$9.18 left")
    }

    func testUsageAfterBaselineKeepsSameQuotaBase() throws {
        let previous = OpenRouterUsageState(
            totalCredits: 10,
            totalUsage: 4,
            quotaBaseCredits: 10,
            usageAtQuotaBase: 0
        )
        let parsed = try XCTUnwrap(OpenRouterUsageParsing.parse(
            fromCreditsData: data(forCredits: 10, usage: 5),
            previousState: previous
        ))

        XCTAssertEqual(parsed.state.quotaBaseCredits, 10)
        XCTAssertEqual(parsed.snapshot.sessionWindow?.remainingPercent, 50)
        XCTAssertEqual(parsed.snapshot.creditValueText, "$5.00 left")
    }

    func testStateStoreRoundTrips() throws {
        let suiteName = "OpenRouterUsageParsingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = OpenRouterUsageState(
            totalCredits: 10.18,
            totalUsage: 1,
            quotaBaseCredits: 10.18,
            usageAtQuotaBase: 0
        )
        let store = OpenRouterUsageStateStore(defaults: defaults)
        store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testZeroCreditAccountRemainsAvailable() {
        let state = OpenRouterUsageState(totalCredits: 0, totalUsage: 0, quotaBaseCredits: 0, usageAtQuotaBase: 0)
        let snapshot = OpenRouterUsageParsing.parse(
            fromCreditsData: data(forCredits: 0, usage: 0),
            previousState: state
        )?.snapshot

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 100)
        XCTAssertEqual(snapshot?.creditValueText, "$0.00 left")
        XCTAssertTrue(snapshot?.isAvailable ?? false)
    }

    func testUsageOverCreditsClampsBalanceAndPercent() {
        let state = OpenRouterUsageState(totalCredits: 5, totalUsage: 0, quotaBaseCredits: 5, usageAtQuotaBase: 0)
        let snapshot = OpenRouterUsageParsing.parse(
            fromCreditsData: data(forCredits: 5, usage: 10),
            previousState: state
        )?.snapshot

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 0)
        XCTAssertEqual(snapshot?.creditValueText, "$0.00 left")
    }

    func testPercentClampedAtHundred() {
        let state = OpenRouterUsageState(totalCredits: 2, totalUsage: 0, quotaBaseCredits: 2, usageAtQuotaBase: 0)
        let snapshot = OpenRouterUsageParsing.parse(
            fromCreditsData: data(forCredits: 2, usage: 4),
            previousState: state
        )?.snapshot

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 0)
    }

    func testMalformedPayloadReturnsNil() {
        XCTAssertNil(OpenRouterUsageParsing.parse(fromCreditsData: Data("not json".utf8)))
        XCTAssertNil(OpenRouterUsageParsing.parse(fromCreditsData: Data("{\"data\":{}}".utf8)))
        XCTAssertNil(OpenRouterUsageParsing.parse(fromCreditsData: Data("{\"data\":{\"total_usage\":1}}".utf8)))
    }
}
