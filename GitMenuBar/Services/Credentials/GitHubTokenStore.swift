import Foundation
import Security

protocol GitHubTokenStore: Sendable {
    func saveToken(_ token: String)
    func storedToken() -> String?
    func deleteStoredToken()
}

final class GitHubKeychainTokenStore: GitHubTokenStore {
    private let service: String
    private let account: String

    init(
        service: String = "com.mourato.GitMenuBar",
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
