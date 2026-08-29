@testable import GitMenuBar
import XCTest

final class AIKeychainStoreTests: XCTestCase {
    func testInMemoryStoreSaveReadUpdateDeleteAPIKey() {
        let store = InMemoryAIAPIKeyStore()
        let providerId = UUID()

        store.saveAPIKey("key-1", for: providerId)
        XCTAssertEqual(store.apiKey(for: providerId), "key-1")

        store.saveAPIKey("key-2", for: providerId)
        XCTAssertEqual(store.apiKey(for: providerId), "key-2")

        store.deleteAPIKey(for: providerId)
        XCTAssertNil(store.apiKey(for: providerId))
    }

    func testSingleBlobStoreReadsMissingItemAsEmptyAndWritesRoundTrip() throws {
        let client = FakeAIKeychainItemClient()
        let store = AIKeychainStore(client: client)
        let credentialID = AIProviderCredentialID.openrouter
        let value = UUID().uuidString

        XCTAssertNil(try store.apiKey(for: credentialID))
        try store.saveAPIKey(value, for: credentialID)

        XCTAssertEqual(try store.apiKey(for: credentialID), value)
        XCTAssertEqual(client.writeCount, 1)
    }

    func testSingleBlobStoreRejectsInvalidPayloadAndWriteFailure() throws {
        let client = FakeAIKeychainItemClient(data: Data("not-json".utf8))
        let store = AIKeychainStore(client: client)

        XCTAssertThrowsError(try store.fetchAllAPIKeys()) { error in
            XCTAssertEqual(error as? AIKeychainStoreError, .invalidPayload)
        }

        client.data = nil
        client.writeError = AIKeychainStoreError.keychain(-1)
        XCTAssertThrowsError(try store.saveAPIKey(UUID().uuidString, for: .google)) { error in
            XCTAssertEqual(error as? AIKeychainStoreError, .keychain(-1))
        }
    }
}

private final class FakeAIKeychainItemClient: AIKeychainItemClient, @unchecked Sendable {
    var data: Data?
    var writeError: Error?
    private(set) var writeCount = 0

    init(data: Data? = nil) {
        self.data = data
    }

    func read(service _: String, account _: String) throws -> Data? {
        data
    }

    func write(_ data: Data, service _: String, account _: String) throws {
        writeCount += 1
        if let writeError {
            throw writeError
        }
        self.data = data
    }

    func delete(service _: String, account _: String) throws {}
}

final class KeychainMigratorTests: XCTestCase {
    private var isolatedDefaultsSuiteNames: [String] = []

    override func tearDown() {
        for suiteName in isolatedDefaultsSuiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        isolatedDefaultsSuiteNames.removeAll()
        super.tearDown()
    }

    func testMalformedLegacyItemThrowsAndLeavesMarkerAndOriginsPending() throws {
        let defaults = isolatedDefaults()
        let client = FakeMigrationClient(items: [
            KeychainMigrator.newServiceTestItem(account: nil, data: Data(UUID().uuidString.utf8))
        ])

        XCTAssertThrowsError(try KeychainMigrator.validateLegacyAIItems(using: client)) { error in
            guard let migrationError = error as? AIKeychainStoreError,
                  case .malformedLegacyItem = migrationError
            else {
                return XCTFail("Expected malformed legacy item")
            }
        }

        KeychainMigrator.migrateToUnifiedDomain(
            destination: InMemoryAIAPIKeyStore(),
            legacyClient: client,
            defaults: defaults,
            migrateGitHub: false,
            migratePreferences: false
        )

        XCTAssertEqual(defaults.integer(forKey: AppPreferences.Keys.aiCredentialMigrationVersion), 0)
        XCTAssertEqual(client.deleteCount, 0)
    }

    func testMissingDataAndInvalidUTF8AreTypedMalformedErrors() {
        let cases: [LegacyKeychainItem] = [
            LegacyKeychainItem(account: "openrouter-api-key", data: nil),
            LegacyKeychainItem(account: "openrouter-api-key", data: Data([0xFF]))
        ]

        for item in cases {
            let client = FakeMigrationClient(items: [(AIKeychainStore.serviceName, item)])
            XCTAssertThrowsError(try KeychainMigrator.validateLegacyAIItems(using: client)) { error in
                guard let migrationError = error as? AIKeychainStoreError,
                      case .malformedLegacyItem = migrationError
                else {
                    return XCTFail("Expected malformed legacy item")
                }
            }
        }
    }

    func testConflictAndReadBackMismatchPreserveOriginsAndMarker() {
        let provider = makeProvider()
        let defaults = isolatedDefaults()
        let account = "provider-\(provider.id.uuidString)"
        let client = FakeMigrationClient(items: [
            KeychainMigrator.newServiceTestItem(account: account, data: Data(UUID().uuidString.utf8)),
            KeychainMigrator.newServiceTestItem(account: account, data: Data(UUID().uuidString.utf8))
        ])
        let destination = FakeMigrationStore(readBack: [:])

        KeychainMigrator.migrateToUnifiedDomain(
            providerConfigs: [provider],
            destination: destination,
            legacyClient: client,
            defaults: defaults,
            migrateGitHub: false,
            migratePreferences: false
        )

        XCTAssertEqual(defaults.integer(forKey: AppPreferences.Keys.aiCredentialMigrationVersion), 0)
        XCTAssertEqual(client.deleteCount, 0)
        XCTAssertEqual(destination.replaceCount, 0)
    }

    func testEqualDuplicateIsWrittenReadBackThenDeletedAndMarkedComplete() throws {
        let provider = makeProvider()
        let defaults = isolatedDefaults()
        let value = UUID().uuidString
        let account = "provider-\(provider.id.uuidString)"
        let client = FakeMigrationClient(items: [
            KeychainMigrator.newServiceTestItem(account: account, data: Data(value.utf8)),
            KeychainMigrator.oldServiceTestItem(account: account, data: Data(value.utf8))
        ])
        let destination = InMemoryAIAPIKeyStore()

        KeychainMigrator.migrateToUnifiedDomain(
            providerConfigs: [provider],
            destination: destination,
            legacyClient: client,
            defaults: defaults,
            migrateGitHub: false,
            migratePreferences: false
        )

        XCTAssertEqual(try destination.apiKey(for: AIProviderCredentialID(provider: provider)), value)
        XCTAssertEqual(client.deleteCount, 2)
        XCTAssertEqual(defaults.integer(forKey: AppPreferences.Keys.aiCredentialMigrationVersion), 1)
    }

    func testReadBackMismatchAndWriteFailureRemainRetryable() {
        let provider = makeProvider()
        let defaults = isolatedDefaults()
        let account = "provider-\(provider.id.uuidString)"
        let client = FakeMigrationClient(items: [
            KeychainMigrator.newServiceTestItem(account: account, data: Data(UUID().uuidString.utf8))
        ])
        let destination = FakeMigrationStore(readBack: [:])

        KeychainMigrator.migrateToUnifiedDomain(
            providerConfigs: [provider], destination: destination, legacyClient: client,
            defaults: defaults, migrateGitHub: false, migratePreferences: false
        )

        XCTAssertEqual(defaults.integer(forKey: AppPreferences.Keys.aiCredentialMigrationVersion), 0)
        XCTAssertEqual(client.deleteCount, 0)
        XCTAssertEqual(destination.replaceCount, 1)

        let failingDestination = FakeMigrationStore(readBack: [:], writeError: AIKeychainStoreError.keychain(-1))
        let failingDefaults = isolatedDefaults()
        let retryClient = FakeMigrationClient(items: [
            KeychainMigrator.newServiceTestItem(account: account, data: Data(UUID().uuidString.utf8))
        ])
        KeychainMigrator.migrateToUnifiedDomain(
            providerConfigs: [provider], destination: failingDestination, legacyClient: retryClient,
            defaults: failingDefaults, migrateGitHub: false, migratePreferences: false
        )

        XCTAssertEqual(failingDefaults.integer(forKey: AppPreferences.Keys.aiCredentialMigrationVersion), 0)
        XCTAssertEqual(retryClient.deleteCount, 0)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "KeychainMigratorTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated test defaults")
        }
        isolatedDefaultsSuiteNames.append(suiteName)
        return defaults
    }

    private func makeProvider() -> AIProviderConfig {
        AIProviderConfig(name: "Provider", type: .openAI, endpointURL: "https://api.openai.com", selectedModel: "model")
    }
}

private extension KeychainMigrator {
    static func newServiceTestItem(account: String?, data: Data?) -> (service: String, item: LegacyKeychainItem) {
        (AIKeychainStore.serviceName, LegacyKeychainItem(account: account, data: data))
    }

    static func oldServiceTestItem(account: String?, data: Data?) -> (service: String, item: LegacyKeychainItem) {
        ("com.pizzaman.GitMenuBar.ai.providers", LegacyKeychainItem(account: account, data: data))
    }
}

private final class FakeMigrationClient: KeychainMigratorItemClient {
    private var items: [(service: String, item: LegacyKeychainItem)]
    private(set) var deleteCount = 0

    init(items: [(service: String, item: LegacyKeychainItem)]) {
        self.items = items
    }

    func fetch(service: String) throws -> [LegacyKeychainItem] {
        items.filter { $0.service == service }.map(\.item)
    }

    func delete(service: String, account: String) throws {
        deleteCount += 1
        items.removeAll { $0.service == service && $0.item.account == account }
    }
}

private final class FakeMigrationStore: AIAPIKeyStore, @unchecked Sendable {
    var values: [AIProviderCredentialID: String] = [:]
    let readBack: [AIProviderCredentialID: String]
    let writeError: Error?
    private(set) var replaceCount = 0

    init(readBack: [AIProviderCredentialID: String], writeError: Error? = nil) {
        self.readBack = readBack
        self.writeError = writeError
    }

    func saveAPIKey(_: String, for _: AIProviderCredentialID) throws {}
    func apiKey(for credentialID: AIProviderCredentialID) throws -> String? {
        values[credentialID]
    }

    func fetchAllAPIKeys() throws -> [AIProviderCredentialID: String] {
        readBack
    }

    func replaceAPIKeys(_ values: [AIProviderCredentialID: String]) throws {
        replaceCount += 1
        if let writeError {
            throw writeError
        }
        self.values = values
    }

    func deleteAPIKey(for _: AIProviderCredentialID) throws {}
}
