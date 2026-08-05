import Foundation
import Security

struct LegacyKeychainItem {
    let account: String?
    let data: Data?
}

protocol KeychainMigratorItemClient {
    func fetch(service: String) throws -> [LegacyKeychainItem]
    func delete(service: String, account: String) throws
}

struct SecurityKeychainMigratorItemClient: KeychainMigratorItemClient {
    func fetch(service: String) throws -> [LegacyKeychainItem] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else { throw AIKeychainStoreError.keychain(status) }
        guard let items = result as? [[String: Any]] else { throw AIKeychainStoreError.invalidPayload }
        return items.map {
            LegacyKeychainItem(
                account: $0[kSecAttrAccount as String] as? String,
                data: $0[kSecValueData as String] as? Data
            )
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

enum KeychainMigrator {
    private static let newService = AIKeychainStore.serviceName
    private static let oldGitHubService = "com.pizzaman.GitMenuBar"
    private static let oldAIService = "com.pizzaman.GitMenuBar.ai.providers"
    private static let migrationVersion = 1

    // swiftlint:disable:next cyclomatic_complexity
    static func migrateToUnifiedDomain(
        providerConfigs: [AIProviderConfig] = AIProviderStore().providers,
        destination: AIAPIKeyStore? = nil,
        legacyClient: any KeychainMigratorItemClient = SecurityKeychainMigratorItemClient(),
        defaults: UserDefaults = .standard,
        migrateGitHub: Bool = true,
        migratePreferences: Bool = true
    ) {
        guard defaults.integer(forKey: AppPreferences.Keys.aiCredentialMigrationVersion) < migrationVersion else {
            return
        }

        let destination = destination ?? AIKeychainStore()
        guard let legacyItems = try? fetchLegacyAIItems(using: legacyClient) else { return }
        let providersByID = Dictionary(uniqueKeysWithValues: providerConfigs.map { ($0.id.uuidString.lowercased(), $0) })
        guard var values = try? destination.fetchAllAPIKeys() else { return }
        var sourcesByIdentity: [AIProviderCredentialID: [LegacySource]] = [:]

        for item in legacyItems {
            let identity: AIProviderCredentialID?
            if item.account == "openrouter-api-key" {
                identity = .openrouter
            } else if item.account.hasPrefix("provider-"),
                      let provider = providersByID[String(item.account.dropFirst("provider-".count)).lowercased()] {
                identity = AIProviderCredentialID(provider: provider)
            } else {
                return
            }

            guard let identity else { return }
            sourcesByIdentity[identity, default: []].append(LegacySource(service: item.service, account: item.account, value: item.value))
        }

        var sourceAccounts: [(service: String, account: String)] = []
        for (identity, sources) in sourcesByIdentity {
            let sourceValues = Set(sources.map(\.value))
            guard sourceValues.count == 1, let value = sourceValues.first else { return }
            if let existing = values[identity], existing != value {
                return
            }
            values[identity] = value
            sourceAccounts.append(contentsOf: sources.map { ($0.service, $0.account) })
        }

        do {
            try destination.replaceAPIKeys(values)
            guard try destination.fetchAllAPIKeys() == values else { return }
            for source in sourceAccounts {
                try legacyClient.delete(service: source.service, account: source.account)
            }
            if migrateGitHub {
                try migrateGitHubToken()
            }
            if migratePreferences {
                migrateUserDefaults()
            }
            defaults.set(migrationVersion, forKey: AppPreferences.Keys.aiCredentialMigrationVersion)
        } catch {
            // Keep all legacy origins and the pending marker for a safe retry.
        }
    }

    private struct LegacyItem {
        let service: String
        let account: String
        let value: String
    }

    private struct LegacySource {
        let service: String
        let account: String
        let value: String
    }

    static func validateLegacyAIItems(using client: any KeychainMigratorItemClient) throws {
        _ = try fetchLegacyAIItems(using: client)
    }

    private static func fetchLegacyAIItems(using client: any KeychainMigratorItemClient) throws -> [LegacyItem] {
        try [newService, oldAIService].flatMap { service in
            try client.fetch(service: service).compactMap { item in
                guard let account = item.account else {
                    throw AIKeychainStoreError.malformedLegacyItem(service: service)
                }
                if account == AIKeychainStore.accountName || account == "github-access-token" {
                    return nil
                }
                guard let data = item.data, let value = String(data: data, encoding: .utf8) else {
                    throw AIKeychainStoreError.malformedLegacyItem(service: service)
                }
                return LegacyItem(service: service, account: account, value: value)
            }
        }
    }

    private static func migrateGitHubToken() throws {
        guard let token = try read(service: oldGitHubService, account: "github-access-token") else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: newService,
            kSecAttrAccount as String: "github-access-token",
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw AIKeychainStoreError.keychain(status) }
        if status == errSecDuplicateItem {
            return
        }
        try delete(service: oldGitHubService, account: "github-access-token")
    }

    private static func migrateUserDefaults() {
        guard let oldDefaults = UserDefaults(suiteName: "com.pizzaman.GitMenuBar") else { return }
        for (key, value) in oldDefaults.dictionaryRepresentation()
            where !key.hasPrefix("Apple") && !key.hasPrefix("NS") && !key.hasPrefix("com.apple") {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    private static func read(service: String, account: String) throws -> String? {
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
        return String(data: data, encoding: .utf8)
    }

    private static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AIKeychainStoreError.keychain(status) }
    }
}
