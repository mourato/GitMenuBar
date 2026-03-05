@testable import GitMenuBar
import XCTest

final class AIProviderStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "AIProviderStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    func testLoadsEmptyStateWhenNoDataExists() {
        let store = AIProviderStore(defaults: defaults)

        XCTAssertEqual(store.providers, [])
        XCTAssertEqual(store.preferences, .default)
    }

    func testPersistsProvidersAndPreferencesAcrossStoreInstances() {
        let store = AIProviderStore(defaults: defaults)
        let provider = makeProvider(name: "OpenAI Team")

        store.upsertProvider(provider)
        store.updateDefaultProvider(provider.id)
        store.updateDefaultModel("gpt-4.1")

        let reloadedStore = AIProviderStore(defaults: defaults)

        XCTAssertEqual(reloadedStore.providers.count, 1)
        XCTAssertEqual(reloadedStore.providers.first?.name, "OpenAI Team")
        XCTAssertEqual(reloadedStore.preferences.defaultProviderId, provider.id)
        XCTAssertEqual(reloadedStore.preferences.defaultModel, "gpt-4.1")
    }

    func testReassignsDefaultProviderWhenCurrentDefaultIsDeleted() {
        let store = AIProviderStore(defaults: defaults)
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

    private func makeProvider(name: String, type: AIProviderType = .openAI) -> AIProviderConfig {
        AIProviderConfig(
            name: name,
            type: type,
            endpointURL: type.defaultEndpoint,
            selectedModel: "model-1",
            availableModels: ["model-1", "model-2"]
        )
    }
}
