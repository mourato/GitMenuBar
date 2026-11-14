import Foundation

protocol GitHubTokenStore: Sendable {
    func saveToken(_ token: String)
    func storedToken() -> String?
    func deleteStoredToken()
    /// Drops the in-memory copy so the next read consults the keychain again.
    func invalidateCachedToken()
}

extension GitHubTokenStore {
    func invalidateCachedToken() {}
}

final class GitHubKeychainTokenStore: GitHubTokenStore, @unchecked Sendable {
    private let service: String
    private let account: String
    private let client: any KeychainItemClient
    private let lock = NSLock()
    /// `nil` means not loaded yet; `.some(nil)` means the keychain has no token.
    private var cachedToken: String??

    init(
        service: String = "com.mourato.GitMenuBar",
        account: String = "github-access-token",
        client: any KeychainItemClient = SecurityKeychainItemClient(accessibility: .afterFirstUnlock)
    ) {
        self.service = service
        self.account = account
        self.client = client
    }

    func saveToken(_ token: String) {
        lock.lock(); defer { lock.unlock() }
        do {
            try client.write(Data(token.utf8), service: service, account: account)
            cachedToken = .some(token)
        } catch {
            print("Error storing token in keychain: \(error)")
        }
    }

    /// Reads the keychain once per unlock; later calls reuse the copy.
    func storedToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cachedToken {
            return cachedToken
        }
        do {
            let data = try client.read(service: service, account: account)
            let token = data.flatMap { String(data: $0, encoding: .utf8) }
            cachedToken = .some(token)
            return token
        } catch {
            // A failed read is not a definitive "no token"; retry on the next call.
            return nil
        }
    }

    func deleteStoredToken() {
        lock.lock(); defer { lock.unlock() }
        try? client.delete(service: service, account: account)
        cachedToken = .some(nil)
    }

    func invalidateCachedToken() {
        lock.lock(); defer { lock.unlock() }
        cachedToken = nil
    }
}
