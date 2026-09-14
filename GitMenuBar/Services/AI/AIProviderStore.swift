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
        providers.removeAll { $0.id == id }
        normalizeDefaults()
        persistProviders()
        persistPreferences()
    }

    func updateDefaultProvider(_ providerId: UUID?) {
        preferences.defaultUsesChatGPT = false
        preferences.defaultProviderId = providerId
        normalizeDefaults()
        persistPreferences()
    }

    func updateDefaultSelection(_ selection: AICommitProviderSelection?) {
        switch selection {
        case .chatGPT:
            preferences.defaultUsesChatGPT = true
            preferences.defaultProviderId = nil
        case let .api(providerId):
            preferences.defaultUsesChatGPT = false
            preferences.defaultProviderId = providerId
        case .defaultProvider, nil:
            preferences.defaultUsesChatGPT = false
            preferences.defaultProviderId = nil
        }
        normalizeDefaults()
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

    func updateFallbackProvider(_ providerId: UUID?) {
        preferences.fallbackUsesChatGPT = false
        preferences.fallbackProviderId = providerId
        normalizeDefaults()
        persistPreferences()
    }

    func updateFallbackSelection(_ selection: AICommitProviderSelection) {
        switch selection {
        case .chatGPT:
            preferences.fallbackUsesChatGPT = true
            preferences.fallbackProviderId = nil
        case let .api(providerId):
            preferences.fallbackUsesChatGPT = false
            preferences.fallbackProviderId = providerId
        case .defaultProvider:
            preferences.fallbackUsesChatGPT = false
            preferences.fallbackProviderId = nil
        }
        normalizeDefaults()
        persistPreferences()
    }

    func updateChatGPTEnabled(_ enabled: Bool) {
        preferences.chatGPTEnabled = enabled
        persistPreferences()
    }

    func updateChatGPTReasoningEffort(_ effort: String?, for model: String) {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        if let effort, !effort.isEmpty {
            preferences.chatGPTReasoningEfforts[model] = effort
        } else {
            preferences.chatGPTReasoningEfforts.removeValue(forKey: model)
        }
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
        guard !preferences.defaultUsesChatGPT else {
            return nil
        }
        guard let id = preferences.defaultProviderId else {
            return providers.first
        }

        return providers.first { $0.id == id }
    }

    var fallbackProvider: AIProviderConfig? {
        guard !usesChatGPTForFallback else {
            return nil
        }
        guard let fallbackProviderId = preferences.fallbackProviderId else {
            return defaultProvider
        }

        return providers.first { $0.id == fallbackProviderId }
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

    var defaultProviderSelection: AICommitProviderSelection? {
        if preferences.defaultUsesChatGPT {
            return .chatGPT
        }
        guard let provider = defaultProvider else { return nil }
        return .api(provider.id)
    }

    var fallbackProviderSelection: AICommitProviderSelection {
        if usesChatGPTForFallback {
            return .chatGPT
        }
        if let fallbackProviderId = preferences.fallbackProviderId {
            return .api(fallbackProviderId)
        }
        return .defaultProvider
    }

    var usesChatGPTForFallback: Bool {
        preferences.fallbackUsesChatGPT
            || (preferences.fallbackProviderId == nil && preferences.defaultUsesChatGPT)
    }

    func chatGPTReasoningEffort(for model: String) -> String? {
        preferences.chatGPTReasoningEfforts[model]
    }

    private func normalizeDefaults() {
        if providers.isEmpty, !preferences.defaultUsesChatGPT {
            preferences.defaultProviderId = nil
            preferences.defaultModel = ""
        }

        normalizeDefaultProvider()
        normalizeFallbackProvider()
        normalizeFallbackModel()
    }

    private func normalizeDefaultProvider() {
        guard !preferences.defaultUsesChatGPT, !providers.isEmpty else {
            if preferences.defaultUsesChatGPT {
                preferences.defaultProviderId = nil
            }
            return
        }

        let hasValidProvider = preferences.defaultProviderId.map { id in
            providers.contains { $0.id == id }
        } ?? false
        if !hasValidProvider {
            preferences.defaultProviderId = providers.first?.id
        }
        guard let provider = defaultProvider else { return }

        let currentModel = preferences.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let availableModels = provider.availableModels.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard currentModel.isEmpty || (!availableModels.isEmpty && !availableModels.contains(currentModel)) else {
            return
        }
        preferences.defaultModel = provider.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferences.defaultModel.isEmpty || (!availableModels.isEmpty && !availableModels.contains(preferences.defaultModel)) {
            preferences.defaultModel = availableModels.first ?? ""
        }
    }

    private func normalizeFallbackProvider() {
        guard !preferences.fallbackUsesChatGPT else {
            preferences.fallbackProviderId = nil
            return
        }

        let hasValidProvider = preferences.fallbackProviderId.map { id in
            providers.contains { $0.id == id }
        } ?? true
        if !hasValidProvider {
            preferences.fallbackProviderId = nil
        }
        if let provider = defaultProvider, preferences.fallbackProviderId == provider.id {
            preferences.fallbackProviderId = nil
        }
    }

    private func normalizeFallbackModel() {
        guard !usesChatGPTForFallback else { return }
        guard let fallbackProvider else {
            preferences.fallbackModel = ""
            return
        }

        let availableModels = fallbackProvider.availableModels.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let model = preferences.fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty, !availableModels.isEmpty, !availableModels.contains(model) {
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
