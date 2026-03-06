@testable import GitMenuBar
import XCTest

final class CredentialStoreCacheTests: XCTestCase {
    func testCachedAIAPIKeyStoreReadsBackingStoreOnlyOncePerProvider() {
        let providerId = UUID()
        let backingStore = SpyAIAPIKeyBackingStore(storage: [providerId: "secret-key"])
        let store = CachedAIAPIKeyStore(backingStore: backingStore)

        XCTAssertEqual(store.apiKey(for: providerId), "secret-key")
        XCTAssertEqual(store.apiKey(for: providerId), "secret-key")
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

private final class SpyAIAPIKeyBackingStore: AIAPIKeyStore {
    private var storage: [UUID: String]

    private(set) var readCount = 0

    init(storage: [UUID: String] = [:]) {
        self.storage = storage
    }

    func saveAPIKey(_ apiKey: String, for providerId: UUID) {
        storage[providerId] = apiKey
    }

    func apiKey(for providerId: UUID) -> String? {
        readCount += 1
        return storage[providerId]
    }

    func deleteAPIKey(for providerId: UUID) {
        storage.removeValue(forKey: providerId)
    }
}

private final class SpyGitHubTokenBackingStore: GitHubTokenStore {
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
