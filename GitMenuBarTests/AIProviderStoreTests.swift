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
        store.updateDefaultModel("model-2")

        let reloadedStore = AIProviderStore(dataStore: dataStore)

        XCTAssertEqual(reloadedStore.providers.count, 1)
        XCTAssertEqual(reloadedStore.providers.first?.name, "OpenAI Team")
        XCTAssertEqual(reloadedStore.providers.first?.hasStoredAPIKey, true)
        XCTAssertEqual(reloadedStore.preferences.defaultProviderId, provider.id)
        XCTAssertEqual(reloadedStore.preferences.defaultModel, "model-2")
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

    func testSwitchingDefaultProviderKeepsModelSupportedByBothProviders() {
        let store = AIProviderStore(dataStore: dataStore)
        let firstProvider = makeProvider(name: "First")
        let secondProvider = makeProvider(name: "Second", type: .anthropic)
        store.upsertProvider(firstProvider)
        store.upsertProvider(secondProvider)
        store.updateDefaultProvider(firstProvider.id)
        store.updateDefaultModel("model-2")

        store.updateDefaultProvider(secondProvider.id)

        XCTAssertEqual(store.preferences.defaultModel, "model-2")
    }

    func testSwitchingDefaultProviderReplacesUnsupportedModelWithSelectedModel() {
        let store = AIProviderStore(dataStore: dataStore)
        let firstProvider = makeProvider(name: "First")
        let secondProvider = AIProviderConfig(
            name: "Second",
            type: .anthropic,
            endpointURL: AIProviderType.anthropic.defaultEndpoint,
            selectedModel: "claude-sonnet",
            availableModels: ["claude-sonnet", "claude-haiku"]
        )
        store.upsertProvider(firstProvider)
        store.upsertProvider(secondProvider)
        store.updateDefaultProvider(firstProvider.id)
        store.updateDefaultModel("")

        store.updateDefaultProvider(secondProvider.id)

        XCTAssertEqual(store.preferences.defaultModel, "claude-sonnet")
    }

    func testProviderWithoutModelListUsesItsSelectedModel() {
        let store = AIProviderStore(dataStore: dataStore)
        let firstProvider = makeProvider(name: "First")
        let secondProvider = AIProviderConfig(
            name: "Second",
            type: .anthropic,
            endpointURL: AIProviderType.anthropic.defaultEndpoint,
            selectedModel: "custom-model"
        )
        store.upsertProvider(firstProvider)
        store.upsertProvider(secondProvider)
        store.updateDefaultProvider(firstProvider.id)
        store.updateDefaultModel("")

        store.updateDefaultProvider(secondProvider.id)

        XCTAssertEqual(store.preferences.defaultModel, "custom-model")
    }

    func testDeletingDefaultProviderNormalizesReplacementModel() {
        let store = AIProviderStore(dataStore: dataStore)
        let firstProvider = AIProviderConfig(
            name: "First",
            type: .openAI,
            endpointURL: AIProviderType.openAI.defaultEndpoint,
            selectedModel: "gpt-4.1",
            availableModels: ["gpt-4.1"]
        )
        let secondProvider = AIProviderConfig(
            name: "Second",
            type: .anthropic,
            endpointURL: AIProviderType.anthropic.defaultEndpoint,
            selectedModel: "claude-sonnet",
            availableModels: ["claude-sonnet"]
        )
        store.upsertProvider(firstProvider)
        store.upsertProvider(secondProvider)
        store.updateDefaultProvider(secondProvider.id)
        store.updateDefaultModel("claude-sonnet")

        store.deleteProvider(id: secondProvider.id)

        XCTAssertEqual(store.preferences.defaultProviderId, firstProvider.id)
        XCTAssertEqual(store.preferences.defaultModel, "gpt-4.1")
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

    func testCredentialIdentityNormalizesOpenRouterSubdomainsAndKeepsCustomEndpointsSeparate() {
        let openRouter = AIProviderConfig(
            name: "Provider", type: .openAI, endpointURL: "https://gateway.OPENROUTER.ai:443/", selectedModel: "model"
        )
        let openRouterPath = AIProviderConfig(
            name: "Provider", type: .openAI, endpointURL: "https://openrouter.ai/api/v1", selectedModel: "model"
        )
        let custom = AIProviderConfig(
            name: "Provider", type: .openAI, endpointURL: "https://api.openai.com/v1", selectedModel: "model"
        )
        let malformed = AIProviderConfig(
            name: "Provider", type: .gemini, endpointURL: "not a URL", selectedModel: "model"
        )

        XCTAssertEqual(AIProviderCredentialID(provider: openRouter), .openrouter)
        XCTAssertEqual(AIProviderCredentialID(provider: openRouterPath), .openrouter)
        XCTAssertEqual(AIProviderCredentialID(provider: custom).rawValue, "custom:\(custom.id.uuidString.lowercased())")
        XCTAssertEqual(AIProviderCredentialID(provider: malformed).rawValue, "custom:\(malformed.id.uuidString.lowercased())")
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
