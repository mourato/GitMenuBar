@testable import GitMenuBar
import Security
import XCTest

final class KeychainItemClientTests: XCTestCase {
    func testItemQueryCarriesTheSharedAccessGroup() {
        let query = SecurityKeychainItemClient.itemQuery(
            service: "com.mourato.GitMenuBar",
            account: "github-access-token",
            accessGroup: KeychainAccessGroup.identifier
        )

        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "com.mourato.GitMenuBar")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "github-access-token")
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "com.mourato.GitMenuBar")
    }

    func testItemQueryOmitsAccessGroupWhenSigningHasNone() {
        let query = SecurityKeychainItemClient.itemQuery(service: "s", account: "a", accessGroup: nil)

        XCTAssertNil(query[kSecAttrAccessGroup as String])
        XCTAssertEqual(query[kSecAttrService as String] as? String, "s")
    }
}

/// Isolated stand-in for the keychain. Tests never reach the login keychain.
final class FakeKeychainItemClient: KeychainItemClient, @unchecked Sendable {
    var data: Data?
    var readError: Error?
    var writeError: Error?
    var deleteError: Error?
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var deleteCount = 0
    private(set) var lastService: String?
    private(set) var lastAccount: String?

    init(data: Data? = nil) {
        self.data = data
    }

    func read(service: String, account: String) throws -> Data? {
        readCount += 1
        lastService = service
        lastAccount = account
        if let readError {
            throw readError
        }
        return data
    }

    func write(_ data: Data, service: String, account: String) throws {
        writeCount += 1
        lastService = service
        lastAccount = account
        if let writeError {
            throw writeError
        }
        self.data = data
    }

    func delete(service: String, account: String) throws {
        deleteCount += 1
        lastService = service
        lastAccount = account
        if let deleteError {
            throw deleteError
        }
        data = nil
    }
}
