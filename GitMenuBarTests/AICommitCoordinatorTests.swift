@testable import GitMenuBar
import XCTest

@MainActor
final class AICommitCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "AICommitCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    func testReadinessUsesStoredAPIKeyAsSourceOfTruth() {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: false)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore(storage: [provider.id: "secret-key"])
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore
        )

        XCTAssertTrue(coordinator.isReadyForGeneration)
        XCTAssertEqual(coordinator.generationDisabledReason, "")
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, true)
        XCTAssertGreaterThanOrEqual(apiKeyStore.readCount, 1)
    }

    func testSaveAndDeleteAPIKeyUpdatesStoredFlag() {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: false)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore()
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore
        )

        coordinator.saveAPIKey("secret-key", for: provider.id)
        XCTAssertEqual(apiKeyStore.saveCount, 1)
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, true)

        coordinator.deleteAPIKey(for: provider.id)
        XCTAssertEqual(apiKeyStore.deleteCount, 1)
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, false)
    }

    func testGenerateMessageReadsAPIKeyOnlyWhenInvoked() async {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: true)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore(storage: [provider.id: "secret-key"])
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore,
            repositoryPathOverride: ""
        )

        XCTAssertEqual(apiKeyStore.readCount, 0)

        do {
            _ = try await coordinator.generateMessage(scopeOverride: nil)
            XCTFail("Expected generateMessage to fail without a diff")
        } catch {
            guard let aiError = error as? AIError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(aiError, .noDiffAvailable)
        }

        XCTAssertEqual(apiKeyStore.readCount, 1)
    }

    func testGenerateMessageClearsStoredFlagWhenKeyIsMissing() async {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: true)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore()
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore
        )

        do {
            _ = try await coordinator.generateMessage(scopeOverride: nil)
            XCTFail("Expected missing API key error")
        } catch {
            guard let aiError = error as? AIError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(aiError, .apiKeyMissing)
        }

        XCTAssertEqual(apiKeyStore.readCount, 1)
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, false)
        XCTAssertEqual(
            coordinator.generationDisabledReason,
            "Add an API key for the default provider in Settings to enable commit generation."
        )
    }

    func testReadinessClearsStoredFlagWhenKeyIsMissing() {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: true)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore()
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore
        )

        XCTAssertFalse(coordinator.isReadyForGeneration)
        XCTAssertEqual(
            coordinator.generationDisabledReason,
            "Add an API key for the default provider in Settings to enable commit generation."
        )
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, false)
    }

    private func makeProviderStore() -> AIProviderStore {
        AIProviderStore(defaults: defaults)
    }

    private func makeCoordinator(
        providerStore: AIProviderStore,
        apiKeyStore: any AIAPIKeyStore,
        repositoryPathOverride: String = "/tmp"
    ) -> AICommitCoordinator {
        AICommitCoordinator(
            providerStore: providerStore,
            keychainStore: apiKeyStore,
            messageService: AICommitMessageService(),
            gitManager: GitManager(repositoryPathOverride: repositoryPathOverride)
        )
    }

    private func makeProvider(hasStoredAPIKey: Bool) -> AIProviderConfig {
        AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://api.openai.com",
            selectedModel: "gpt-4.1",
            availableModels: ["gpt-4.1"],
            hasStoredAPIKey: hasStoredAPIKey
        )
    }
}

private final class SpyAIAPIKeyStore: AIAPIKeyStore {
    private var storage: [UUID: String]

    private(set) var readCount = 0
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    init(storage: [UUID: String] = [:]) {
        self.storage = storage
    }

    func saveAPIKey(_ apiKey: String, for providerId: UUID) {
        saveCount += 1
        storage[providerId] = apiKey
    }

    func apiKey(for providerId: UUID) -> String? {
        readCount += 1
        return storage[providerId]
    }

    func deleteAPIKey(for providerId: UUID) {
        deleteCount += 1
        storage.removeValue(forKey: providerId)
    }
}
