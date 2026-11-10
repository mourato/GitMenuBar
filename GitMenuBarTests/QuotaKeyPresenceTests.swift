@testable import GitMenuBar
import XCTest

/// Presence cache backing the quota settings status pill: stored keys surface
/// as suffixes without touching the Keychain from view bodies.
@MainActor
final class QuotaKeyPresenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "QuotaKeyPresenceTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated test defaults")
        }
        defaults = isolatedDefaults
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRefreshCachesSuffixesForStoredKeys() {
        let preferences = UsageQuotaPresentationPreferences(
            defaults: defaults,
            keyStore: InMemoryAIAPIKeyStore(storage: [AIProviderCredentialID.opencodego: "stored-key-1234"])
        )

        preferences.refreshQuotaKeyPresence()

        XCTAssertEqual(preferences.quotaKeySuffixes[.opencodeGo], "1234")
        XCTAssertNil(preferences.quotaKeySuffixes[.openrouter])
    }

    func testRefreshClearsSuffixAfterDelete() throws {
        let keyStore = InMemoryAIAPIKeyStore(storage: [AIProviderCredentialID.opencodego: "stored-key-1234"])
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults, keyStore: keyStore)

        preferences.refreshQuotaKeyPresence()
        XCTAssertEqual(preferences.quotaKeySuffixes[.opencodeGo], "1234")

        try keyStore.deleteAPIKey(for: AIProviderCredentialID.opencodego)
        preferences.refreshQuotaKeyPresence()

        XCTAssertNil(preferences.quotaKeySuffixes[.opencodeGo])
    }
}
