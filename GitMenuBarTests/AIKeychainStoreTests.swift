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
        let client = FakeKeychainItemClient()
        let store = AIKeychainStore(client: client)
        let credentialID = AIProviderCredentialID.openrouter
        let value = UUID().uuidString

        XCTAssertNil(try store.apiKey(for: credentialID))
        try store.saveAPIKey(value, for: credentialID)

        XCTAssertEqual(try store.apiKey(for: credentialID), value)
        XCTAssertEqual(client.writeCount, 1)
        XCTAssertEqual(client.readCount, 1)
    }

    func testSingleBlobStoreRejectsInvalidPayloadAndWriteFailure() throws {
        let client = FakeKeychainItemClient(data: Data("not-json".utf8))
        let store = AIKeychainStore(client: client)

        XCTAssertThrowsError(try store.fetchAllAPIKeys()) { error in
            XCTAssertEqual(error as? KeychainItemError, .invalidPayload)
        }

        client.data = nil
        client.writeError = KeychainItemError.keychain(-1)
        XCTAssertThrowsError(try store.saveAPIKey(UUID().uuidString, for: .google)) { error in
            XCTAssertEqual(error as? KeychainItemError, .keychain(-1))
        }
    }

    func testSingleBlobStoreReadsKeychainOncePerInstance() throws {
        let client = FakeKeychainItemClient()
        let writer = AIKeychainStore(client: client)
        try writer.saveAPIKey("key-cached", for: .openrouter)
        let readsBefore = client.readCount

        let reader = AIKeychainStore(client: client)
        XCTAssertEqual(try reader.apiKey(for: .openrouter), "key-cached")
        XCTAssertEqual(try reader.apiKey(for: .openrouter), "key-cached")
        XCTAssertEqual(try reader.fetchAllAPIKeys()[.openrouter], "key-cached")
        XCTAssertEqual(client.readCount, readsBefore + 1)
    }

    func testInvalidateCachedCredentialsForcesAKeychainReread() throws {
        let client = FakeKeychainItemClient()
        let store = AIKeychainStore(client: client)
        try store.saveAPIKey("key-rejected", for: .opencodego)
        let readsBefore = client.readCount

        store.invalidateCachedCredentials()

        XCTAssertEqual(try store.apiKey(for: .opencodego), "key-rejected")
        XCTAssertEqual(client.readCount, readsBefore + 1)
    }

    func testSaveUpdatesTheCopyWithoutRereadingTheKeychain() throws {
        let client = FakeKeychainItemClient()
        let store = AIKeychainStore(client: client)
        try store.saveAPIKey("key-1", for: .openai)
        let readsAfterFirstWrite = client.readCount

        try store.saveAPIKey("key-2", for: .openai)

        XCTAssertEqual(client.readCount, readsAfterFirstWrite)
        XCTAssertEqual(client.writeCount, 2)
        XCTAssertEqual(try store.apiKey(for: .openai), "key-2")
    }
}
