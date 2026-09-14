@testable import GitMenuBar
import XCTest

final class CodexAppServerProtocolTests: XCTestCase {
    func testRequestAndNotificationUseNewlineDelimitedJSON() throws {
        let request = try CodexAppServerProtocol.request(id: 7, method: "model/list")
        let notification = try CodexAppServerProtocol.notification(method: "initialized")

        XCTAssertEqual(request.last, 0x0A)
        XCTAssertEqual(notification.last, 0x0A)
        XCTAssertTrue(String(bytes: request, encoding: .utf8)?.contains("\"id\":7") == true)
        XCTAssertTrue(String(bytes: notification, encoding: .utf8)?.contains("\"method\":\"initialized\"") == true)
    }

    func testParsesResponsesNotificationsAndServerRequests() {
        let response = CodexAppServerProtocol.parse(Data("{\"id\":3,\"result\":{\"ok\":true}}".utf8))
        let notification = CodexAppServerProtocol.parse(Data("{\"method\":\"turn/completed\",\"params\":{}}".utf8))
        let request = CodexAppServerProtocol.parse(Data("{\"id\":\"server-1\",\"method\":\"tool/requestUserInput\",\"params\":{}}".utf8))

        guard case let .response(id, result) = response else { return XCTFail("Expected response") }
        XCTAssertEqual(id, 3)
        XCTAssertEqual(result["ok"]?.boolValue, true)
        guard case let .notification(method, _) = notification else { return XCTFail("Expected notification") }
        XCTAssertEqual(method, "turn/completed")
        guard case let .request(id, method, _) = request else { return XCTFail("Expected server request") }
        XCTAssertEqual(id, .string("server-1"))
        XCTAssertEqual(method, "tool/requestUserInput")
    }
}
