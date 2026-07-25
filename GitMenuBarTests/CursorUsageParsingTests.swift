@testable import GitMenuBar
import XCTest

final class CursorUsageParsingTests: XCTestCase {
    func testSessionCookieValueBuildsWorkosToken() {
        let token = makeJWT(sub: "auth0|user_redacted_123")
        XCTAssertEqual(
            CursorUsageParsing.sessionCookieValue(accessToken: token),
            "user_redacted_123%3A%3A\(token)"
        )
    }

    func testSessionCookieValueReturnsNilForMalformedJWT() {
        XCTAssertNil(CursorUsageParsing.sessionCookieValue(accessToken: "not-a-jwt"))
    }

    func testSnapshotFromUsageSummaryMapsRemainingPercentAndReset() throws {
        let root: [String: Any] = [
            "billingCycleStart": "2026-04-02T14:11:55.000Z",
            "billingCycleEnd": "2026-05-02T14:11:55.000Z",
            "membershipType": "pro",
            "isUnlimited": false,
            "individualUsage": [
                "plan": [
                    "enabled": true,
                    "used": 1500,
                    "limit": 2000,
                    "remaining": 500,
                    "totalPercentUsed": 75.0,
                    "breakdown": [
                        "included": 1500,
                        "bonus": 0,
                        "total": 2000
                    ]
                ],
                "onDemand": [
                    "enabled": true,
                    "used": 0,
                    "limit": NSNull(),
                    "remaining": NSNull()
                ]
            ]
        ]

        let snapshot = CursorUsageParsing.snapshot(fromUsageSummary: root)

        XCTAssertEqual(snapshot?.providerID, .cursor)
        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 25)
        XCTAssertEqual(snapshot?.sessionWindow?.intervalChip, "30d")
        XCTAssertEqual(snapshot?.sessionWindow?.durationSeconds, 30 * 86400)
        XCTAssertEqual(snapshot?.creditValueText, "$5.00 left")
        XCTAssertEqual(snapshot?.statusNote, "cursor usage-summary api")

        let resetAt = try XCTUnwrap(snapshot?.sessionWindow?.resetAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(formatter.string(from: resetAt), "2026-05-02T14:11:55.000Z")
    }

    func testSnapshotFromUsageSummaryUsesUsedAndLimitWhenPercentMissing() {
        let root: [String: Any] = [
            "billingCycleEnd": "2026-05-02T14:11:55.000Z",
            "isUnlimited": false,
            "individualUsage": [
                "plan": [
                    "enabled": true,
                    "used": 500,
                    "limit": 2000,
                    "remaining": 1500
                ],
                "onDemand": ["enabled": false]
            ]
        ]

        let snapshot = CursorUsageParsing.snapshot(fromUsageSummary: root)
        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 75)
    }

    func testSnapshotFromUsageSummaryHandlesUnlimitedPlan() {
        let root: [String: Any] = [
            "billingCycleEnd": "2026-05-02T14:11:55.000Z",
            "isUnlimited": true,
            "individualUsage": [
                "plan": [
                    "enabled": true,
                    "used": 9999,
                    "limit": 0,
                    "remaining": 0
                ],
                "onDemand": ["enabled": false]
            ]
        ]

        let snapshot = CursorUsageParsing.snapshot(fromUsageSummary: root)
        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 100)
        XCTAssertEqual(snapshot?.creditValueText, "Unlimited")
    }

    func testSnapshotFromUsageSummaryReturnsNilWhenPlanMissing() {
        XCTAssertNil(CursorUsageParsing.snapshot(fromUsageSummary: ["individualUsage": [:]]))
    }

    func testSnapshotFromUsageSummaryDataDecodesJSON() {
        let json = """
        {
          "billingCycleEnd": "2026-05-02T14:11:55.000Z",
          "isUnlimited": false,
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 1000,
              "limit": 2000,
              "remaining": 1000,
              "totalPercentUsed": 50
            },
            "onDemand": { "enabled": false }
          }
        }
        """
        let snapshot = CursorUsageParsing.snapshot(fromUsageSummary: Data(json.utf8))
        XCTAssertEqual(snapshot?.sessionWindow?.remainingPercent, 50)
    }

    private func makeJWT(sub: String) -> String {
        let header = Data("{}".utf8).base64EncodedString()
        guard let payloadData = try? JSONSerialization.data(withJSONObject: ["sub": sub]) else {
            return "invalid.invalid.invalid"
        }
        let payloadPart = payloadData.base64EncodedString()
        return "\(header).\(payloadPart).signature"
    }
}
