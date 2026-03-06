import Foundation
import Security

protocol GitHubTokenStore {
    func saveToken(_ token: String)
    func storedToken() -> String?
    func deleteStoredToken()
}

final class GitHubKeychainTokenStore: GitHubTokenStore {
    private let service: String
    private let account: String

    init(
        service: String = "com.pizzaman.GitMenuBar",
        account: String = "github-access-token"
    ) {
        self.service = service
        self.account = account
    }

    func saveToken(_ token: String) {
        let data = Data(token.utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error storing token in keychain: \(status)")
        }
    }

    func storedToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    func deleteStoredToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class InMemoryGitHubTokenStore: GitHubTokenStore {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func saveToken(_ token: String) {
        self.token = token
    }

    func storedToken() -> String? {
        token
    }

    func deleteStoredToken() {
        token = nil
    }
}

final class CachedGitHubTokenStore: GitHubTokenStore {
    private enum CacheEntry {
        case unresolved
        case missing
        case value(String)
    }

    private let backingStore: any GitHubTokenStore
    private let lock = NSLock()
    private var cacheEntry: CacheEntry = .unresolved

    init(backingStore: any GitHubTokenStore) {
        self.backingStore = backingStore
    }

    func saveToken(_ token: String) {
        backingStore.saveToken(token)
        lock.lock()
        cacheEntry = .value(token)
        lock.unlock()
    }

    func storedToken() -> String? {
        lock.lock()
        let cachedEntry = cacheEntry
        lock.unlock()

        switch cachedEntry {
        case .missing:
            return nil
        case let .value(token):
            return token
        case .unresolved:
            let token = backingStore.storedToken()
            lock.lock()
            cacheEntry = token.map(CacheEntry.value) ?? .missing
            lock.unlock()
            return token
        }
    }

    func deleteStoredToken() {
        backingStore.deleteStoredToken()
        lock.lock()
        cacheEntry = .missing
        lock.unlock()
    }
}
