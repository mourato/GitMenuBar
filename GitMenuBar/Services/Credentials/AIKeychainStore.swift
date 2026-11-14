import Foundation

private struct AIKeychainPayload: Codable, Equatable {
    let version: Int
    var values: [String: String]
}

protocol AIAPIKeyStore: Sendable {
    func saveAPIKey(_ apiKey: String, for credentialID: AIProviderCredentialID) throws
    func apiKey(for credentialID: AIProviderCredentialID) throws -> String?
    func fetchAllAPIKeys() throws -> [AIProviderCredentialID: String]
    func replaceAPIKeys(_ values: [AIProviderCredentialID: String]) throws
    func deleteAPIKey(for credentialID: AIProviderCredentialID) throws
    /// Drops the in-memory copy so the next read consults the keychain again.
    func invalidateCachedCredentials()
}

extension AIAPIKeyStore {
    func invalidateCachedCredentials() {}
}

final class AIKeychainStore: AIAPIKeyStore, @unchecked Sendable {
    static let serviceName = "com.mourato.GitMenuBar"
    static let accountName = "ai-api-keys.v1"

    private let service: String
    private let account: String
    private let client: any KeychainItemClient
    private let lock = NSLock()
    private var cachedValues: [AIProviderCredentialID: String]?

    init(
        service: String = AIKeychainStore.serviceName,
        account: String = AIKeychainStore.accountName,
        client: any KeychainItemClient = SecurityKeychainItemClient()
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

    func invalidateCachedCredentials() {
        lock.lock(); defer { lock.unlock() }
        cachedValues = nil
    }

    /// Reads the single keychain blob once per unlock; later calls reuse the copy.
    private func readValues() throws -> [AIProviderCredentialID: String] {
        if let cachedValues {
            return cachedValues
        }
        guard let data = try client.read(service: service, account: account) else {
            cachedValues = [:]
            return [:]
        }
        guard let payload = try? JSONDecoder().decode(AIKeychainPayload.self, from: data), payload.version == 1 else {
            throw KeychainItemError.invalidPayload
        }
        var values: [AIProviderCredentialID: String] = [:]
        for (key, value) in payload.values {
            guard key.hasPrefix("custom:") || ["openrouter", "opencodego", "google", "openai", "anthropic"].contains(key) else {
                throw KeychainItemError.invalidPayload
            }
            values[AIProviderCredentialID(rawValue: key)] = value
        }
        cachedValues = values
        return values
    }

    private func writeValues(_ values: [AIProviderCredentialID: String]) throws {
        let payload = AIKeychainPayload(version: 1, values: values.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value })
        try client.write(JSONEncoder().encode(payload), service: service, account: account)
        cachedValues = values
    }
}
