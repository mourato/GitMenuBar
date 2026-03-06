@testable import GitMenuBar
import XCTest

final class AIKeychainStoreTests: XCTestCase {
    func testInMemoryStoreSaveReadUpdateDeleteAPIKey() {
        let store = InMemoryAIAPIKeyStore()
        let providerId = UUID()

        store.saveAPIKey("key-1", for: providerId)
        XCTAssertEqual(store.apiKey(for: providerId), "key-1")

        store.saveAPIKey("key-2", for: providerId)
        XCTAssertEqual(store.apiKey(for: providerId), "key-2")

        store.deleteAPIKey(for: providerId)
        XCTAssertNil(store.apiKey(for: providerId))
    }
}
