@testable import GitMenuBar
import XCTest

final class AIProviderStoreTests: XCTestCase {
    private var dataStore: InMemoryAIProviderStoreDataStore!

    override func setUp() {
        super.setUp()
        dataStore = InMemoryAIProviderStoreDataStore()
    }

    override func tearDown() {
        dataStore = nil
        super.tearDown()
    }

    func testLoadsEmptyStateWhenNoDataExists() {
        let store = AIProviderStore(dataStore: dataStore)

        XCTAssertEqual(store.providers, [])
        XCTAssertEqual(store.preferences, .default)
    }

    func testPersistsProvidersAndPreferencesAcrossStoreInstances() {
        let store = AIProviderStore(dataStore: dataStore)
        let provider = makeProvider(name: "OpenAI Team", hasStoredAPIKey: true)

        store.upsertProvider(provider)
        store.updateDefaultProvider(provider.id)
        store.updateDefaultModel("gpt-4.1")

        let reloadedStore = AIProviderStore(dataStore: dataStore)

        XCTAssertEqual(reloadedStore.providers.count, 1)
        XCTAssertEqual(reloadedStore.providers.first?.name, "OpenAI Team")
        XCTAssertEqual(reloadedStore.providers.first?.hasStoredAPIKey, true)
        XCTAssertEqual(reloadedStore.preferences.defaultProviderId, provider.id)
        XCTAssertEqual(reloadedStore.preferences.defaultModel, "gpt-4.1")
    }

    func testReassignsDefaultProviderWhenCurrentDefaultIsDeleted() {
        let store = AIProviderStore(dataStore: dataStore)
        let firstProvider = makeProvider(name: "First", type: .openAI)
        let secondProvider = makeProvider(name: "Second", type: .anthropic)

        store.upsertProvider(firstProvider)
        store.upsertProvider(secondProvider)
        store.updateDefaultProvider(secondProvider.id)

        store.deleteProvider(id: secondProvider.id)

        XCTAssertEqual(store.providers.count, 1)
        XCTAssertEqual(store.providers.first?.id, firstProvider.id)
        XCTAssertEqual(store.preferences.defaultProviderId, firstProvider.id)
    }

    func testLegacyProviderPayloadDefaultsStoredKeyFlagToFalse() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 123_456_789)
        let payload = """
        [
          {
            "id":"\(UUID().uuidString)",
            "name":"Legacy Provider",
            "type":"openai",
            "endpointURL":"https://api.openai.com",
            "selectedModel":"gpt-4.1",
            "availableModels":["gpt-4.1"],
            "createdAt":\(referenceDate.timeIntervalSinceReferenceDate),
            "updatedAt":\(referenceDate.timeIntervalSinceReferenceDate)
          }
        ]
        """
        guard let payloadData = payload.data(using: .utf8) else {
            return XCTFail("Failed to encode payload as UTF-8 data")
        }
        dataStore.set(payloadData, forKey: "aiProviderConfigs.v1")

        let store = AIProviderStore(dataStore: dataStore)

        XCTAssertEqual(store.providers.count, 1)
        XCTAssertEqual(store.providers.first?.hasStoredAPIKey, false)
    }

    func testCredentialIdentityUsesStableBackendNotDisplayName() {
        let openRouter = AIProviderConfig(
            name: "Anything", type: .openAI, endpointURL: "HTTPS://API.OPENROUTER.AI:443/", selectedModel: "model"
        )
        let openAI = AIProviderConfig(
            name: "Renamed", type: .openAI, endpointURL: "https://api.openai.com:443/", selectedModel: "model"
        )
        let gemini = AIProviderConfig(
            name: "Google", type: .gemini, endpointURL: "https://generativelanguage.googleapis.com/", selectedModel: "model"
        )
        let custom = AIProviderConfig(name: "Custom", type: .openAI, endpointURL: "not a URL", selectedModel: "model")

        XCTAssertEqual(AIProviderCredentialID(provider: openRouter), .openrouter)
        XCTAssertEqual(AIProviderCredentialID(provider: openAI), .openai)
        XCTAssertEqual(AIProviderCredentialID(provider: gemini), .google)
        XCTAssertEqual(AIProviderCredentialID(provider: custom).rawValue, "custom:\(custom.id.uuidString.lowercased())")
    }

    private func makeProvider(
        name: String,
        type: AIProviderType = .openAI,
        hasStoredAPIKey: Bool = false
    ) -> AIProviderConfig {
        AIProviderConfig(
            name: name,
            type: type,
            endpointURL: type.defaultEndpoint,
            selectedModel: "model-1",
            availableModels: ["model-1", "model-2"],
            hasStoredAPIKey: hasStoredAPIKey
        )
    }
}
