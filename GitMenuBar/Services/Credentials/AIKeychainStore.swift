import Foundation
import Security

protocol AIAPIKeyStore {
    func saveAPIKey(_ apiKey: String, for providerId: UUID)
    func apiKey(for providerId: UUID) -> String?
    func fetchAllAPIKeys() -> [UUID: String]
    func deleteAPIKey(for providerId: UUID)
}

final class AIKeychainStore: AIAPIKeyStore {
    private let service: String

    init(service: String = "com.mourato.GitMenuBar") {
        self.service = service
    }

    func saveAPIKey(_ apiKey: String, for providerId: UUID) {
        let account = accountName(for: providerId)
        let data = Data(apiKey.utf8)

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

        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func apiKey(for providerId: UUID) -> String? {
        let account = accountName(for: providerId)
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
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return key
    }

    func fetchAllAPIKeys() -> [UUID: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return [:]
        }

        var allKeys: [UUID: String] = [:]

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix("provider-"),
                  let data = item[kSecValueData as String] as? Data,
                  let key = String(data: data, encoding: .utf8)
            else {
                continue
            }

            let uuidString = account.replacingOccurrences(of: "provider-", with: "")
            if let uuid = UUID(uuidString: uuidString) {
                allKeys[uuid] = key
            }
        }

        return allKeys
    }

    func deleteAPIKey(for providerId: UUID) {
        let account = accountName(for: providerId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    private func accountName(for providerId: UUID) -> String {
        "provider-\(providerId.uuidString)"
    }
}

final class InMemoryAIAPIKeyStore: AIAPIKeyStore {
    private var storage: [UUID: String]

    init(storage: [UUID: String] = [:]) {
        self.storage = storage
    }

    func saveAPIKey(_ apiKey: String, for providerId: UUID) {
        storage[providerId] = apiKey
    }

    func apiKey(for providerId: UUID) -> String? {
        storage[providerId]
    }

    func fetchAllAPIKeys() -> [UUID: String] {
        storage
    }

    func deleteAPIKey(for providerId: UUID) {
        storage.removeValue(forKey: providerId)
    }
}

final class CachedAIAPIKeyStore: AIAPIKeyStore {
    private enum CacheEntry {
        case missing
        case value(String)
    }

    private let backingStore: any AIAPIKeyStore
    private var storage: [UUID: CacheEntry] = [:]
    private var hasPreloadedAll: Bool = false
    private let lock = NSLock()

    init(backingStore: any AIAPIKeyStore) {
        self.backingStore = backingStore
    }

    func preloadAllKeys() {
        let allKeys = backingStore.fetchAllAPIKeys()
        lock.lock()
        for (id, key) in allKeys {
            storage[id] = .value(key)
        }
        hasPreloadedAll = true
        lock.unlock()
    }

    func saveAPIKey(_ apiKey: String, for providerId: UUID) {
        backingStore.saveAPIKey(apiKey, for: providerId)
        lock.lock()
        storage[providerId] = .value(apiKey)
        lock.unlock()
    }

    func apiKey(for providerId: UUID) -> String? {
        lock.lock()
        if let cachedValue = storage[providerId] {
            lock.unlock()
            switch cachedValue {
            case .missing:
                return nil
            case let .value(apiKey):
                return apiKey
            }
        }
        lock.unlock()

        let apiKey = backingStore.apiKey(for: providerId)

        lock.lock()
        if let apiKey {
            storage[providerId] = .value(apiKey)
        } else {
            storage[providerId] = .missing
        }
        lock.unlock()

        return apiKey
    }

    func fetchAllAPIKeys() -> [UUID: String] {
        lock.lock()
        let preloaded = hasPreloadedAll
        lock.unlock()

        if preloaded {
            lock.lock()
            let currentStorage = storage
            lock.unlock()

            var result: [UUID: String] = [:]
            for (id, entry) in currentStorage {
                if case let .value(key) = entry {
                    result[id] = key
                }
            }
            return result
        }

        // If not preloaded, fetch all from backing store and update cache
        let allKeys = backingStore.fetchAllAPIKeys()

        lock.lock()
        for (id, key) in allKeys {
            storage[id] = .value(key)
        }
        hasPreloadedAll = true
        lock.unlock()

        return allKeys
    }

    func deleteAPIKey(for providerId: UUID) {
        backingStore.deleteAPIKey(for: providerId)
        lock.lock()
        storage[providerId] = .missing
        lock.unlock()
    }
}
