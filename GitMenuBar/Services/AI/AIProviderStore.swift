import Foundation

protocol AIProviderStoreDataStore {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

struct UserDefaultsAIProviderStoreDataStore: AIProviderStoreDataStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

final class InMemoryAIProviderStoreDataStore: AIProviderStoreDataStore {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) {
        values[key] = data
    }
}

final class AIProviderStore: ObservableObject {
    @Published private(set) var providers: [AIProviderConfig] = []
    @Published private(set) var preferences: AICommitPreferences = .default

    private let dataStore: any AIProviderStoreDataStore
    private let providersKey = "aiProviderConfigs.v1"
    private let preferencesKey = "aiCommitPreferences.v1"

    init(defaults: UserDefaults = .standard) {
        dataStore = UserDefaultsAIProviderStoreDataStore(defaults: defaults)
        load()
    }

    init(dataStore: any AIProviderStoreDataStore) {
        self.dataStore = dataStore
        load()
    }

    func load() {
        if let providersData = dataStore.data(forKey: providersKey),
           let decodedProviders = try? JSONDecoder().decode([AIProviderConfig].self, from: providersData)
        {
            providers = decodedProviders
        } else {
            providers = []
        }

        if let preferencesData = dataStore.data(forKey: preferencesKey),
           let decodedPreferences = try? JSONDecoder().decode(AICommitPreferences.self, from: preferencesData)
        {
            preferences = decodedPreferences
        } else {
            preferences = .default
        }

        normalizeDefaults()
    }

    func upsertProvider(_ provider: AIProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }

        providers.sort { $0.createdAt < $1.createdAt }
        normalizeDefaults()
        persistProviders()
        persistPreferences()
    }

    func deleteProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        normalizeDefaults()
        persistProviders()
        persistPreferences()
    }

    func updateDefaultProvider(_ providerId: UUID?) {
        preferences.defaultProviderId = providerId

        if let provider = defaultProvider,
           preferences.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            preferences.defaultModel = provider.selectedModel
        }

        normalizeDefaults()
        persistPreferences()
    }

    func updateDefaultModel(_ model: String) {
        preferences.defaultModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        persistPreferences()
    }

    func updateStoredAPIKeyPresence(_ hasStoredAPIKey: Bool, for providerId: UUID) {
        guard let index = providers.firstIndex(where: { $0.id == providerId }) else {
            return
        }

        providers[index].hasStoredAPIKey = hasStoredAPIKey
        providers[index].updatedAt = Date()
        persistProviders()
    }

    func updateDefaultScopeMode(_ mode: AICommitDefaultScopeMode) {
        preferences.defaultScopeMode = mode
        persistPreferences()
    }

    var defaultProvider: AIProviderConfig? {
        guard let id = preferences.defaultProviderId else {
            return providers.first
        }

        return providers.first { $0.id == id }
    }

    func effectiveDefaultModel() -> String {
        let explicitModel = preferences.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitModel.isEmpty {
            return explicitModel
        }

        return defaultProvider?.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func normalizeDefaults() {
        if providers.isEmpty {
            preferences.defaultProviderId = nil
            preferences.defaultModel = ""
            return
        }

        if let selectedId = preferences.defaultProviderId,
           !providers.contains(where: { $0.id == selectedId })
        {
            preferences.defaultProviderId = providers.first?.id
        }

        if preferences.defaultProviderId == nil {
            preferences.defaultProviderId = providers.first?.id
        }

        if let provider = defaultProvider,
           preferences.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            preferences.defaultModel = provider.selectedModel
        }
    }

    private func persistProviders() {
        if let encoded = try? JSONEncoder().encode(providers) {
            dataStore.set(encoded, forKey: providersKey)
        }
    }

    private func persistPreferences() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            dataStore.set(encoded, forKey: preferencesKey)
        }
    }
}
