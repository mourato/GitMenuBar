@testable import GitMenuBar
import XCTest

final class CredentialStoreCacheTests: XCTestCase {
    func testCachedAIAPIKeyStoreReadsBackingStoreOnlyOncePerProvider() {
        let providerId = UUID()
        let credentialID = AIProviderCredentialID(rawValue: "custom:\(providerId.uuidString.lowercased())")
        let backingStore = SpyAIAPIKeyBackingStore(storage: [credentialID: "secret-key"])
        let store = CachedAIAPIKeyStore(backingStore: backingStore)

        XCTAssertEqual(try store.apiKey(for: credentialID), "secret-key")
        XCTAssertEqual(try store.apiKey(for: credentialID), "secret-key")
        XCTAssertEqual(backingStore.readCount, 1)
    }

    func testCachedGitHubTokenStoreReadsBackingStoreOnlyOnce() {
        let backingStore = SpyGitHubTokenBackingStore(token: "gho_test")
        let store = CachedGitHubTokenStore(backingStore: backingStore)

        XCTAssertEqual(store.storedToken(), "gho_test")
        XCTAssertEqual(store.storedToken(), "gho_test")
        XCTAssertEqual(backingStore.readCount, 1)
    }

    func testCachedGitHubTokenStoreUpdatesCacheOnDelete() {
        let backingStore = SpyGitHubTokenBackingStore(token: "gho_test")
        let store = CachedGitHubTokenStore(backingStore: backingStore)

        XCTAssertEqual(store.storedToken(), "gho_test")
        store.deleteStoredToken()

        XCTAssertNil(store.storedToken())
        XCTAssertEqual(backingStore.readCount, 1)
        XCTAssertEqual(backingStore.deleteCount, 1)
    }
}

private final class SpyAIAPIKeyBackingStore: AIAPIKeyStore, @unchecked Sendable {
    private var storage: [AIProviderCredentialID: String]

    private(set) var readCount = 0

    init(storage: [AIProviderCredentialID: String] = [:]) {
        self.storage = storage
    }

    func saveAPIKey(_ apiKey: String, for providerId: AIProviderCredentialID) throws {
        storage[providerId] = apiKey
    }

    func apiKey(for providerId: AIProviderCredentialID) throws -> String? {
        readCount += 1
        return storage[providerId]
    }

    func fetchAllAPIKeys() throws -> [AIProviderCredentialID: String] {
        storage
    }

    func replaceAPIKeys(_ values: [AIProviderCredentialID: String]) throws {
        storage = values
    }

    func deleteAPIKey(for providerId: AIProviderCredentialID) throws {
        storage.removeValue(forKey: providerId)
    }
}

private final class SpyGitHubTokenBackingStore: GitHubTokenStore, @unchecked Sendable {
    private var token: String?

    private(set) var readCount = 0
    private(set) var deleteCount = 0

    init(token: String?) {
        self.token = token
    }

    func saveToken(_ token: String) {
        self.token = token
    }

    func storedToken() -> String? {
        readCount += 1
        return token
    }

    func deleteStoredToken() {
        deleteCount += 1
        token = nil
    }
}
