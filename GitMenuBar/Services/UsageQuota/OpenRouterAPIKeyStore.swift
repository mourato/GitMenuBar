import Foundation
import Security

protocol OpenRouterAPIKeyStoring: Sendable {
    func loadKey() -> String?
    func saveKey(_ apiKey: String)
    func deleteKey()
}

/// Keychain storage for the OpenRouter API key, scoped to a fixed account.
/// Mirrors the SecItem usage in `AIKeychainStore`.
struct OpenRouterAPIKeyStore: OpenRouterAPIKeyStoring {
    private let service: String
    private let account: String

    init(service: String = "com.mourato.GitMenuBar", account: String = "openrouter-api-key") {
        self.service = service
        self.account = account
    }

    func loadKey() -> String? {
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
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    func saveKey(_ apiKey: String) {
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
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func deleteKey() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }
}

final class InMemoryOpenRouterAPIKeyStore: OpenRouterAPIKeyStoring, @unchecked Sendable {
    private var stored: String?
    private let lock = NSLock()

    func loadKey() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func saveKey(_ apiKey: String) {
        lock.lock()
        stored = apiKey
        lock.unlock()
    }

    func deleteKey() {
        lock.lock()
        stored = nil
        lock.unlock()
    }
}
