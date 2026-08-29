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
    /// App AI prefs use the app suite (same plist as `.standard` in the app).
    nonisolated(unsafe) static let sharedDefaults = UserDefaults(suiteName: "com.mourato.GitMenuBar") ?? .standard

    @Published private(set) var providers: [AIProviderConfig] = []
    @Published private(set) var preferences: AICommitPreferences = .default

    private let dataStore: any AIProviderStoreDataStore
    private let providersKey = "aiProviderConfigs.v1"
    private let preferencesKey = "aiCommitPreferences.v1"

    init(defaults: UserDefaults = AIProviderStore.sharedDefaults) {
        dataStore = UserDefaultsAIProviderStoreDataStore(defaults: defaults)
        load()
    }

    init(dataStore: any AIProviderStoreDataStore) {
        self.dataStore = dataStore
        load()
    }

    func load() {
        let decodedProviders = dataStore.data(forKey: providersKey).flatMap { data in
            try? JSONDecoder().decode([AIProviderConfig].self, from: data)
        }
        if let decodedProviders {
            providers = decodedProviders
        } else {
            providers = []
        }

        let decodedPreferences = dataStore.data(forKey: preferencesKey).flatMap { data in
            try? JSONDecoder().decode(AICommitPreferences.self, from: data)
        }
        if let decodedPreferences {
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
        let previousDefaultProviderID = preferences.defaultProviderId
        providers.removeAll { $0.id == id }
        normalizeDefaults()
        if previousDefaultProviderID != preferences.defaultProviderId {
            preferences.fallbackModel = ""
        }
        persistProviders()
        persistPreferences()
    }

    func updateDefaultProvider(_ providerId: UUID?) {
        let previousDefaultProviderID = preferences.defaultProviderId
        preferences.defaultProviderId = providerId
        normalizeDefaults()
        if previousDefaultProviderID != preferences.defaultProviderId {
            preferences.fallbackModel = ""
        }
        persistPreferences()
    }

    func updateDefaultModel(_ model: String) {
        preferences.defaultModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        persistPreferences()
    }

    func updateFallbackModel(_ model: String) {
        preferences.fallbackModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func effectiveFallbackModel() -> String {
        preferences.fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeDefaults() {
        if providers.isEmpty {
            preferences.defaultProviderId = nil
            preferences.defaultModel = ""
            preferences.fallbackModel = ""
            return
        }

        let hasValidDefaultProvider = preferences.defaultProviderId.map { selectedId in
            providers.contains(where: { $0.id == selectedId })
        } ?? false
        if preferences.defaultProviderId != nil, !hasValidDefaultProvider {
            preferences.defaultProviderId = providers.first?.id
        }

        if preferences.defaultProviderId == nil {
            preferences.defaultProviderId = providers.first?.id
        }

        guard let provider = defaultProvider else {
            preferences.defaultModel = ""
            return
        }

        let currentModel = preferences.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let availableModels = provider.availableModels.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if currentModel.isEmpty || (!availableModels.isEmpty && !availableModels.contains(currentModel)) {
            preferences.defaultModel = provider.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if preferences.defaultModel.isEmpty || (!availableModels.isEmpty && !availableModels.contains(preferences.defaultModel)) {
                preferences.defaultModel = availableModels.first ?? ""
            }
        }

        let fallbackModel = preferences.fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackModel.isEmpty, !availableModels.isEmpty, !availableModels.contains(fallbackModel) {
            preferences.fallbackModel = ""
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
