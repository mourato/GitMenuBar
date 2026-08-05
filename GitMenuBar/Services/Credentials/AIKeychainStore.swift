import Foundation
import Security

enum AIKeychainStoreError: Error, Equatable {
    case keychain(OSStatus)
    case invalidPayload
    case malformedLegacyItem(service: String)
}

protocol AIKeychainItemClient {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct SecurityAIKeychainItemClient: AIKeychainItemClient {
    func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw AIKeychainStoreError.keychain(status) }
        guard let data = result as? Data else { throw AIKeychainStoreError.invalidPayload }
        return data
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else { throw AIKeychainStoreError.keychain(updateStatus) }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw AIKeychainStoreError.keychain(addStatus)
        }
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else { throw AIKeychainStoreError.keychain(retryStatus) }
        }
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIKeychainStoreError.keychain(status)
        }
    }
}

private struct AIKeychainPayload: Codable, Equatable {
    let version: Int
    var values: [String: String]
}

protocol AIAPIKeyStore {
    func saveAPIKey(_ apiKey: String, for credentialID: AIProviderCredentialID) throws
    func apiKey(for credentialID: AIProviderCredentialID) throws -> String?
    func fetchAllAPIKeys() throws -> [AIProviderCredentialID: String]
    func replaceAPIKeys(_ values: [AIProviderCredentialID: String]) throws
    func deleteAPIKey(for credentialID: AIProviderCredentialID) throws
}

final class AIKeychainStore: AIAPIKeyStore {
    static let serviceName = "com.mourato.GitMenuBar"
    static let accountName = "ai-api-keys.v1"

    private let service: String
    private let account: String
    private let client: any AIKeychainItemClient
    private let lock = NSLock()

    init(
        service: String = AIKeychainStore.serviceName,
        account: String = AIKeychainStore.accountName,
        client: any AIKeychainItemClient = SecurityAIKeychainItemClient()
    ) {
        self.service = service
        self.account = account
        self.client = client
    }

    func saveAPIKey(_ apiKey: String, for credentialID: AIProviderCredentialID) throws {
        lock.lock(); defer { lock.unlock() }
        var values = try readValues()
        values[credentialID] = apiKey
        try writeValues(values)
    }

    func apiKey(for credentialID: AIProviderCredentialID) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return try readValues()[credentialID]
    }

    func fetchAllAPIKeys() throws -> [AIProviderCredentialID: String] {
        lock.lock(); defer { lock.unlock() }
        return try readValues()
    }

    func replaceAPIKeys(_ values: [AIProviderCredentialID: String]) throws {
        lock.lock(); defer { lock.unlock() }
        try writeValues(values)
    }

    func deleteAPIKey(for credentialID: AIProviderCredentialID) throws {
        lock.lock(); defer { lock.unlock() }
        var values = try readValues()
        values.removeValue(forKey: credentialID)
        try writeValues(values)
    }

    private func readValues() throws -> [AIProviderCredentialID: String] {
        guard let data = try client.read(service: service, account: account) else { return [:] }
        guard let payload = try? JSONDecoder().decode(AIKeychainPayload.self, from: data), payload.version == 1 else {
            throw AIKeychainStoreError.invalidPayload
        }
        var values: [AIProviderCredentialID: String] = [:]
        for (key, value) in payload.values {
            guard key.hasPrefix("custom:") || ["openrouter", "google", "openai", "anthropic"].contains(key) else {
                throw AIKeychainStoreError.invalidPayload
            }
            values[AIProviderCredentialID(rawValue: key)] = value
        }
        return values
    }

    private func writeValues(_ values: [AIProviderCredentialID: String]) throws {
        let payload = AIKeychainPayload(version: 1, values: values.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value })
        try client.write(JSONEncoder().encode(payload), service: service, account: account)
    }
}

final class InMemoryAIAPIKeyStore: AIAPIKeyStore {
    private var storage: [AIProviderCredentialID: String]

    init(storage: [AIProviderCredentialID: String] = [:]) {
        self.storage = storage
    }

    convenience init(storage: [UUID: String]) {
        self.init(storage: storage.reduce(into: [:]) { result, entry in
            result[AIProviderCredentialID(rawValue: "custom:\(entry.key.uuidString.lowercased())")] = entry.value
        })
    }

    func saveAPIKey(_ apiKey: String, for providerID: UUID) {
        storage[AIProviderCredentialID(rawValue: "custom:\(providerID.uuidString.lowercased())")] = apiKey
    }

    func apiKey(for providerID: UUID) -> String? {
        storage[AIProviderCredentialID(rawValue: "custom:\(providerID.uuidString.lowercased())")]
    }

    func deleteAPIKey(for providerID: UUID) {
        storage.removeValue(forKey: AIProviderCredentialID(rawValue: "custom:\(providerID.uuidString.lowercased())"))
    }

    func saveAPIKey(_ apiKey: String, for credentialID: AIProviderCredentialID) throws {
        storage[credentialID] = apiKey
    }

    func apiKey(for credentialID: AIProviderCredentialID) throws -> String? {
        storage[credentialID]
    }

    func fetchAllAPIKeys() throws -> [AIProviderCredentialID: String] {
        storage
    }

    func replaceAPIKeys(_ values: [AIProviderCredentialID: String]) throws {
        storage = values
    }

    func deleteAPIKey(for credentialID: AIProviderCredentialID) throws {
        storage.removeValue(forKey: credentialID)
    }
}

final class CachedAIAPIKeyStore: AIAPIKeyStore {
    static let shared = CachedAIAPIKeyStore(backingStore: AIKeychainStore())
    private enum CacheEntry { case missing, value(String) }
    private let backingStore: any AIAPIKeyStore
    private var storage: [AIProviderCredentialID: CacheEntry] = [:]
    private var hasPreloadedAll = false
    private let lock = NSLock()

    init(backingStore: any AIAPIKeyStore) {
        self.backingStore = backingStore
    }

    func preloadAllKeys() throws {
        lock.lock(); defer { lock.unlock() }
        let values = try backingStore.fetchAllAPIKeys()
        storage = Dictionary(uniqueKeysWithValues: values.map { ($0.key, .value($0.value)) })
        hasPreloadedAll = true
    }

    func saveAPIKey(_ apiKey: String, for credentialID: AIProviderCredentialID) throws {
        lock.lock(); defer { lock.unlock() }
        try backingStore.saveAPIKey(apiKey, for: credentialID)
        storage[credentialID] = .value(apiKey)
    }

    func apiKey(for credentialID: AIProviderCredentialID) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if let entry = storage[credentialID] {
            if case let .value(value) = entry {
                return value
            }
            return nil
        }
        let value = try backingStore.apiKey(for: credentialID)
        storage[credentialID] = value.map(CacheEntry.value) ?? .missing
        return value
    }

    func fetchAllAPIKeys() throws -> [AIProviderCredentialID: String] {
        lock.lock(); defer { lock.unlock() }
        if !hasPreloadedAll {
            let values = try backingStore.fetchAllAPIKeys()
            storage = Dictionary(uniqueKeysWithValues: values.map { ($0.key, .value($0.value)) })
            hasPreloadedAll = true
        }
        return storage.reduce(into: [:]) { result, entry in
            if case let .value(value) = entry.value {
                result[entry.key] = value
            }
        }
    }

    func replaceAPIKeys(_ values: [AIProviderCredentialID: String]) throws {
        lock.lock(); defer { lock.unlock() }
        try backingStore.replaceAPIKeys(values)
        storage = Dictionary(uniqueKeysWithValues: values.map { ($0.key, .value($0.value)) })
        hasPreloadedAll = true
    }

    func deleteAPIKey(for credentialID: AIProviderCredentialID) throws {
        lock.lock(); defer { lock.unlock() }
        try backingStore.deleteAPIKey(for: credentialID)
        storage[credentialID] = .missing
    }
}
