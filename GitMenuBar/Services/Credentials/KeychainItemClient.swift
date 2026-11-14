import Foundation
import Security

enum KeychainItemError: Error, Equatable {
    case keychain(OSStatus)
    case invalidPayload
}

/// Access group shared by every stored credential. The value must stay in sync with
/// the `keychain-access-groups` entry in
/// `GitMenuBar/GitMenuBar-KeychainAccessGroups.entitlements`.
enum KeychainAccessGroup {
    static let identifier = "com.mourato.GitMenuBar"
}

/// Accessibility applied when an item is created. Each store keeps the contract it
/// already had so existing items are not rewritten with a different policy.
enum KeychainItemAccessibility {
    case afterFirstUnlock
    case whenUnlockedThisDeviceOnly

    var attribute: CFString {
        switch self {
        case .afterFirstUnlock:
            kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlockedThisDeviceOnly:
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}

protocol KeychainItemClient: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct SecurityKeychainItemClient: KeychainItemClient {
    private let accessGroup: String?
    private let accessibility: KeychainItemAccessibility

    init(
        accessGroup: String? = KeychainAccessGroup.identifier,
        accessibility: KeychainItemAccessibility = .whenUnlockedThisDeviceOnly
    ) {
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }

    /// Query for one generic-password item. The legacy file keychain ignores
    /// `kSecAttrAccessGroup`; it becomes authoritative once the signature carries a
    /// provisioning profile that authorizes the group.
    static func itemQuery(service: String, account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    func read(service: String, account: String) throws -> Data? {
        var query = Self.itemQuery(service: service, account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw KeychainItemError.keychain(status) }
        guard let data = result as? Data else { throw KeychainItemError.invalidPayload }
        return data
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query = Self.itemQuery(service: service, account: account, accessGroup: accessGroup)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility.attribute
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else { throw KeychainItemError.keychain(updateStatus) }
        try addItem(query: query, attributes: attributes)
    }

    private func addItem(query: [String: Any], attributes: [String: Any]) throws {
        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus != errSecDuplicateItem else {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else { throw KeychainItemError.keychain(retryStatus) }
            return
        }
        guard addStatus == errSecSuccess else { throw KeychainItemError.keychain(addStatus) }
    }

    func delete(service: String, account: String) throws {
        let query = Self.itemQuery(service: service, account: account, accessGroup: accessGroup)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainItemError.keychain(status)
        }
    }
}
