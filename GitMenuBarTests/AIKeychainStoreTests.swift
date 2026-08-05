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

    func testSingleBlobStoreReadsMissingItemAsEmptyAndWritesRoundTrip() throws {
        let client = FakeAIKeychainItemClient()
        let store = AIKeychainStore(client: client)
        let credentialID = AIProviderCredentialID.openrouter
        let value = UUID().uuidString

        XCTAssertNil(try store.apiKey(for: credentialID))
        try store.saveAPIKey(value, for: credentialID)

        XCTAssertEqual(try store.apiKey(for: credentialID), value)
        XCTAssertEqual(client.writeCount, 1)
    }

    func testSingleBlobStoreRejectsInvalidPayloadAndWriteFailure() throws {
        let client = FakeAIKeychainItemClient(data: Data("not-json".utf8))
        let store = AIKeychainStore(client: client)

        XCTAssertThrowsError(try store.fetchAllAPIKeys()) { error in
            XCTAssertEqual(error as? AIKeychainStoreError, .invalidPayload)
        }

        client.data = nil
        client.writeError = AIKeychainStoreError.keychain(-1)
        XCTAssertThrowsError(try store.saveAPIKey(UUID().uuidString, for: .google)) { error in
            XCTAssertEqual(error as? AIKeychainStoreError, .keychain(-1))
        }
    }
}

private final class FakeAIKeychainItemClient: AIKeychainItemClient {
    var data: Data?
    var writeError: Error?
    private(set) var writeCount = 0

    init(data: Data? = nil) {
        self.data = data
    }

    func read(service _: String, account _: String) throws -> Data? {
        data
    }

    func write(_ data: Data, service _: String, account _: String) throws {
        writeCount += 1
        if let writeError {
            throw writeError
        }
        self.data = data
    }

    func delete(service _: String, account _: String) throws {}
}
