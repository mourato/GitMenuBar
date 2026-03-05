import Foundation

@MainActor
final class AICommitCoordinator: ObservableObject {
    @Published private(set) var isGenerating: Bool = false
    @Published var generationError: String?

    private let providerStore: AIProviderStore
    private let keychainStore: AIKeychainStore
    private let messageService: AICommitMessageService
    private let gitManager: GitManager

    init(
        providerStore: AIProviderStore,
        keychainStore: AIKeychainStore,
        messageService: AICommitMessageService,
        gitManager: GitManager
    ) {
        self.providerStore = providerStore
        self.keychainStore = keychainStore
        self.messageService = messageService
        self.gitManager = gitManager
    }

    func generateMessage(scopeOverride: DiffScope?) async throws -> String {
        generationError = nil

        guard let provider = providerStore.defaultProvider else {
            throw AIError.providerNotConfigured
        }

        let apiKey = keychainStore.apiKey(for: provider.id)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            throw AIError.apiKeyMissing
        }

        let model = providerStore.effectiveDefaultModel()
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.modelNotConfigured
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await messageService.generateCommitMessage(
                provider: provider,
                apiKey: apiKey,
                model: model,
                preferredScopeMode: providerStore.preferences.defaultScopeMode,
                overrideScope: scopeOverride,
                gitManager: gitManager
            )
        } catch {
            generationError = error.localizedDescription
            throw error
        }
    }

    func testConnectionAndFetchModels(
        providerType: AIProviderType,
        endpointURL: String,
        apiKey: String
    ) async throws -> [String] {
        try await messageService.testConnection(
            providerType: providerType,
            endpointURL: endpointURL,
            apiKey: apiKey
        )
    }

    func apiKey(for providerId: UUID) -> String {
        keychainStore.apiKey(for: providerId) ?? ""
    }

    func saveAPIKey(_ apiKey: String, for providerId: UUID) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychainStore.deleteAPIKey(for: providerId)
        } else {
            keychainStore.saveAPIKey(trimmed, for: providerId)
        }
    }

    func deleteAPIKey(for providerId: UUID) {
        keychainStore.deleteAPIKey(for: providerId)
    }

    var isReadyForGeneration: Bool {
        guard let provider = providerStore.defaultProvider else {
            return false
        }

        let hasAPIKey = !(keychainStore.apiKey(for: provider.id)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasModel = !providerStore.effectiveDefaultModel().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return hasAPIKey && hasModel
    }

    var generationDisabledReason: String {
        guard let provider = providerStore.defaultProvider else {
            return "Configure at least one AI provider in Settings to enable commit generation."
        }

        let hasAPIKey = !(keychainStore.apiKey(for: provider.id)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if !hasAPIKey {
            return "Add an API key for the default provider in Settings to enable commit generation."
        }

        let hasModel = !providerStore.effectiveDefaultModel().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasModel {
            return "Choose a default model in Settings to enable commit generation."
        }

        return ""
    }
}
