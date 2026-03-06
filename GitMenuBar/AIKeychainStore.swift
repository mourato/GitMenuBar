import Foundation
import Security

protocol AIAPIKeyStore {
    func saveAPIKey(_ apiKey: String, for providerId: UUID)
    func apiKey(for providerId: UUID) -> String?
    func deleteAPIKey(for providerId: UUID)
}

final class AIKeychainStore: AIAPIKeyStore {
    private let service: String

    init(service: String = "com.pizzaman.GitMenuBar.ai.providers") {
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
    private let lock = NSLock()

    init(backingStore: any AIAPIKeyStore) {
        self.backingStore = backingStore
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

    func deleteAPIKey(for providerId: UUID) {
        backingStore.deleteAPIKey(for: providerId)
        lock.lock()
        storage[providerId] = .missing
        lock.unlock()
    }
}
