#if DEBUG
    import Foundation

    // MARK: - InMemoryGitHubTokenStore

    final class InMemoryGitHubTokenStore: GitHubTokenStore, @unchecked Sendable {
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

    // MARK: - InMemoryAIAPIKeyStore

    final class InMemoryAIAPIKeyStore: AIAPIKeyStore, @unchecked Sendable {
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

    // MARK: - InMemoryAIProviderStoreDataStore

    final class InMemoryAIProviderStoreDataStore: AIProviderStoreDataStore {
        private var values: [String: Data] = [:]

        func data(forKey key: String) -> Data? {
            values[key]
        }

        func set(_ data: Data, forKey key: String) {
            values[key] = data
        }
    }
#endif
