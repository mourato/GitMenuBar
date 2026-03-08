import Foundation
import Security

enum KeychainMigrator {
    private static let newService = "com.mourato.GitMenuBar"
    private static let oldGitHubService = "com.pizzaman.GitMenuBar"
    private static let oldAIService = "com.pizzaman.GitMenuBar.ai.providers"

    static func migrateToUnifiedDomain() {
        // Did we already migrate? Check UserDefaults
        if UserDefaults.standard.bool(forKey: AppPreferences.Keys.hasMigratedKeychainDomain) {
            return
        }

        var didMigrateSomething = false

        // 0. Migrate UserDefaults
        if let oldDefaults = UserDefaults(suiteName: "com.pizzaman.GitMenuBar") {
            let oldDict = oldDefaults.dictionaryRepresentation()
            for (key, value) in oldDict {
                // Ignore system-injected preference keys that usually start with Apple, NS, or com.apple
                if !key.hasPrefix("Apple") && !key.hasPrefix("NS") && !key.hasPrefix("com.apple") {
                    UserDefaults.standard.set(value, forKey: key)
                    didMigrateSomething = true
                }
            }
            print("GitMenuBar: Migrated UserDefaults to unified domain.")
        }

        // 1. Migrate GitHub Token
        if let oldToken = fetchGitHubToken(fromService: oldGitHubService) {
            saveGitHubToken(oldToken, toService: newService)
            deleteGitHubToken(fromService: oldGitHubService)
            didMigrateSomething = true
            print("GitMenuBar: Migrated GitHub token to unified domain.")
        }

        // 2. Migrate AI Provider Keys
        let oldAIKeys = fetchAllAIKeys(fromService: oldAIService)
        if !oldAIKeys.isEmpty {
            for (uuid, apiKey) in oldAIKeys {
                saveAIKey(apiKey, for: uuid, toService: newService)
                deleteAIKey(for: uuid, fromService: oldAIService)
            }
            didMigrateSomething = true
            print("GitMenuBar: Migrated \(oldAIKeys.count) AI keys to unified domain.")
        }

        // Set flag so we don't attempt this again
        UserDefaults.standard.set(true, forKey: AppPreferences.Keys.hasMigratedKeychainDomain)

        if !didMigrateSomething {
            print("GitMenuBar: No legacy keychain items found to migrate.")
        }
    }

    // MARK: - Private Helpers

    private static func fetchGitHubToken(fromService service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "github-access-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private static func saveGitHubToken(_ token: String, toService service: String) {
        let data = Data(token.utf8)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "github-access-token",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func deleteGitHubToken(fromService service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "github-access-token"
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func fetchAllAIKeys(fromService service: String) -> [UUID: String] {
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

    private static func saveAIKey(_ key: String, for uuid: UUID, toService service: String) {
        let account = "provider-\(uuid.uuidString)"
        let data = Data(key.utf8)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func deleteAIKey(for uuid: UUID, fromService service: String) {
        let account = "provider-\(uuid.uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
