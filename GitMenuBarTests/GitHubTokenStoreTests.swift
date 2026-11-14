@testable import GitMenuBar
import XCTest

final class GitHubTokenStoreTests: XCTestCase {
    func testStoredTokenReadsKeychainOnceAndThenServesTheCopy() {
        let client = FakeKeychainItemClient(data: Data("token-a".utf8))
        let store = GitHubKeychainTokenStore(client: client)

        XCTAssertEqual(store.storedToken(), "token-a")
        XCTAssertEqual(store.storedToken(), "token-a")
        XCTAssertEqual(store.storedToken(), "token-a")
        XCTAssertEqual(client.readCount, 1)
    }

    func testMissingTokenIsCachedAsAbsent() {
        let client = FakeKeychainItemClient()
        let store = GitHubKeychainTokenStore(client: client)

        XCTAssertNil(store.storedToken())
        XCTAssertNil(store.storedToken())
        XCTAssertEqual(client.readCount, 1)
    }

    func testInvalidateCachedTokenForcesAKeychainReread() {
        let client = FakeKeychainItemClient(data: Data("older".utf8))
        let store = GitHubKeychainTokenStore(client: client)
        XCTAssertEqual(store.storedToken(), "older")

        client.data = Data("written-by-another-build".utf8)
        store.invalidateCachedToken()

        XCTAssertEqual(store.storedToken(), "written-by-another-build")
        XCTAssertEqual(client.readCount, 2)
    }

    func testSaveTokenWritesToKeychainAndUpdatesTheCopy() {
        let client = FakeKeychainItemClient()
        let store = GitHubKeychainTokenStore(client: client)

        store.saveToken("token-b")

        XCTAssertEqual(client.writeCount, 1)
        XCTAssertEqual(client.lastService, "com.mourato.GitMenuBar")
        XCTAssertEqual(client.lastAccount, "github-access-token")
        XCTAssertEqual(store.storedToken(), "token-b")
        XCTAssertEqual(client.readCount, 0)
    }

    func testDeleteStoredTokenClearsKeychainAndCopy() {
        let client = FakeKeychainItemClient()
        let store = GitHubKeychainTokenStore(client: client)
        store.saveToken("token-c")

        store.deleteStoredToken()

        XCTAssertEqual(client.deleteCount, 1)
        XCTAssertNil(store.storedToken())
        XCTAssertEqual(client.readCount, 0)
    }

    func testReadFailureIsNotCachedAsAbsent() {
        let client = FakeKeychainItemClient(data: Data("token-e".utf8))
        client.readError = KeychainItemError.keychain(-25308)
        let store = GitHubKeychainTokenStore(client: client)
        XCTAssertNil(store.storedToken())

        client.readError = nil

        XCTAssertEqual(store.storedToken(), "token-e")
        XCTAssertEqual(client.readCount, 2)
    }

    func testStoreUsesInjectedServiceAndAccount() {
        let client = FakeKeychainItemClient(data: Data("token-d".utf8))
        let store = GitHubKeychainTokenStore(service: "custom.service", account: "custom.account", client: client)

        XCTAssertEqual(store.storedToken(), "token-d")
        XCTAssertEqual(client.lastService, "custom.service")
        XCTAssertEqual(client.lastAccount, "custom.account")
    }
}
