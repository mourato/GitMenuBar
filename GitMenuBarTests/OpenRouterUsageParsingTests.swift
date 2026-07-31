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
        let snapshot = OpenRouterUsageParsing.snapshot(fromCreditsData: data(forCredits: 10, usage: 4))

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 60)
        XCTAssertNil(snapshot?.sessionWindow?.resetAt)
        XCTAssertEqual(snapshot?.sessionWindow?.intervalChip, "Credits")
        XCTAssertEqual(snapshot?.creditValueText, "$6.00 left")
        XCTAssertEqual(snapshot?.statusNote, "openrouter credits api")
        XCTAssertTrue(snapshot?.isAvailable ?? false)
        XCTAssertEqual(snapshot?.providerID, .openrouter)
    }

    func testZeroCreditAccountRemainsAvailable() {
        let snapshot = OpenRouterUsageParsing.snapshot(fromCreditsData: data(forCredits: 0, usage: 0))

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 100)
        XCTAssertEqual(snapshot?.creditValueText, "$0.00 left")
        XCTAssertTrue(snapshot?.isAvailable ?? false)
    }

    func testUsageOverCreditsClampsBalanceAndPercent() {
        let snapshot = OpenRouterUsageParsing.snapshot(fromCreditsData: data(forCredits: 5, usage: 10))

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 0)
        XCTAssertEqual(snapshot?.creditValueText, "$0.00 left")
    }

    func testPercentClampedAtHundred() {
        let snapshot = OpenRouterUsageParsing.snapshot(fromCreditsData: data(forCredits: 2, usage: 4))

        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 0)
    }

    func testMalformedPayloadReturnsNil() {
        XCTAssertNil(OpenRouterUsageParsing.snapshot(fromCreditsData: Data("not json".utf8)))
        XCTAssertNil(OpenRouterUsageParsing.snapshot(fromCreditsData: Data("{\"data\":{}}".utf8)))
        XCTAssertNil(OpenRouterUsageParsing.snapshot(fromCreditsData: Data("{\"data\":{\"total_usage\":1}}".utf8)))
    }
}
