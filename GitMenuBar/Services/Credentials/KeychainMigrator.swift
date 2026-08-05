import Foundation
import Security

enum KeychainMigrator {
    private static let newService = AIKeychainStore.serviceName
    private static let oldGitHubService = "com.pizzaman.GitMenuBar"
    private static let oldAIService = "com.pizzaman.GitMenuBar.ai.providers"
    private static let migrationVersion = 1

    // swiftlint:disable:next cyclomatic_complexity
    static func migrateToUnifiedDomain(
        providerConfigs: [AIProviderConfig] = AIProviderStore().providers,
        destination: AIAPIKeyStore? = nil
    ) {
        guard UserDefaults.standard.integer(forKey: AppPreferences.Keys.aiCredentialMigrationVersion) < migrationVersion else {
            return
        }

        let destination = destination ?? AIKeychainStore()
        guard let legacyItems = try? fetchLegacyAIItems() else { return }
        let providersByID = Dictionary(uniqueKeysWithValues: providerConfigs.map { ($0.id.uuidString.lowercased(), $0) })
        guard var values = try? destination.fetchAllAPIKeys() else { return }
        var sourceAccounts: [(service: String, account: String)] = []
        var conflicts = Set<AIProviderCredentialID>()
        var unmappable = false

        for item in legacyItems {
            let identity: AIProviderCredentialID?
            if item.account == "openrouter-api-key" {
                identity = .openrouter
            } else if item.account.hasPrefix("provider-"),
                      let provider = providersByID[String(item.account.dropFirst("provider-".count)).lowercased()] {
                identity = AIProviderCredentialID(provider: provider)
            } else {
                identity = nil
                unmappable = true
            }

            guard let identity else { continue }
            if let existing = values[identity], existing != item.value {
                conflicts.insert(identity)
            } else {
                values[identity] = item.value
                sourceAccounts.append((item.service, item.account))
            }
        }

        for conflict in conflicts {
            values.removeValue(forKey: conflict)
            sourceAccounts.removeAll { account in
                legacyItems.contains { $0.service == account.service && $0.account == account.account &&
                    ((($0.account == "openrouter-api-key") ? AIProviderCredentialID.openrouter : nil) == conflict)
                }
            }
        }

        guard !unmappable, conflicts.isEmpty else { return }
        do {
            try destination.replaceAPIKeys(values)
            guard try destination.fetchAllAPIKeys() == values else { return }
            for source in sourceAccounts {
                try delete(service: source.service, account: source.account)
            }
            try migrateGitHubToken()
            migrateUserDefaults()
            UserDefaults.standard.set(migrationVersion, forKey: AppPreferences.Keys.aiCredentialMigrationVersion)
        } catch {
            // Keep all legacy origins and the pending marker for a safe retry.
        }
    }

    private struct LegacyItem {
        let service: String
        let account: String
        let value: String
    }

    private static func fetchLegacyAIItems() throws -> [LegacyItem] {
        try [newService, oldAIService].flatMap { try fetchLegacyAIItems(from: $0) }
    }

    private static func fetchLegacyAIItems(from service: String) throws -> [LegacyItem] {
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
        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account == "openrouter-api-key" || account.hasPrefix("provider-"),
                  let data = item[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8) else { return nil }
            return LegacyItem(service: service, account: account, value: value)
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
