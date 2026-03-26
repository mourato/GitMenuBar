import Foundation

@MainActor
final class AICommitCoordinator: ObservableObject {
    private struct GenerationDependencies {
        let provider: AIProviderConfig
        let apiKey: String
        let model: String
    }

    @Published private(set) var isGenerating: Bool = false
    @Published var generationError: String?

    private let providerStore: AIProviderStore
    private let keychainStore: any AIAPIKeyStore
    private let messageService: AICommitMessageService
    private let gitManager: GitManager

    init(
        providerStore: AIProviderStore,
        keychainStore: any AIAPIKeyStore,
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

        let dependencies = try resolvedGenerationDependencies()

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await messageService.generateCommitMessage(
                provider: dependencies.provider,
                apiKey: dependencies.apiKey,
                model: dependencies.model,
                preferredScopeMode: providerStore.preferences.defaultScopeMode,
                overrideScope: scopeOverride,
                gitManager: gitManager
            )
        } catch {
            generationError = error.localizedDescription
            throw error
        }
    }

    func generateMessage(
        forRawDiff rawDiff: String,
        scopeDescription: String = "Selected commit"
    ) async throws -> String {
        generationError = nil

        let dependencies = try resolvedGenerationDependencies()

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await messageService.generateCommitMessage(
                provider: dependencies.provider,
                apiKey: dependencies.apiKey,
                model: dependencies.model,
                rawDiff: rawDiff,
                scopeDescription: scopeDescription
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
        let apiKey = keychainStore.apiKey(for: providerId) ?? ""
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providerStore.updateStoredAPIKeyPresence(false, for: providerId)
        }
        return apiKey
    }

    func saveAPIKey(_ apiKey: String, for providerId: UUID) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychainStore.deleteAPIKey(for: providerId)
            providerStore.updateStoredAPIKeyPresence(false, for: providerId)
        } else {
            keychainStore.saveAPIKey(trimmed, for: providerId)
            providerStore.updateStoredAPIKeyPresence(true, for: providerId)
        }
    }

    func deleteAPIKey(for providerId: UUID) {
        keychainStore.deleteAPIKey(for: providerId)
        providerStore.updateStoredAPIKeyPresence(false, for: providerId)
    }

    var isReadyForGeneration: Bool {
        guard let provider = providerStore.defaultProvider else {
            return false
        }

        let hasAPIKey = !resolvedAPIKey(for: provider).isEmpty
        let hasModel = !providerStore.effectiveDefaultModel().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return hasAPIKey && hasModel
    }

    var generationDisabledReason: String {
        guard let provider = providerStore.defaultProvider else {
            return "Configure at least one AI provider in Settings to enable commit generation."
        }

        if resolvedAPIKey(for: provider).isEmpty {
            return "Add an API key for the default provider in Settings to enable commit generation."
        }

        let hasModel = !providerStore.effectiveDefaultModel().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasModel {
            return "Choose a default model in Settings to enable commit generation."
        }

        return ""
    }

    private func resolvedAPIKey(for provider: AIProviderConfig) -> String {
        let apiKey = keychainStore.apiKey(for: provider.id)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasStoredAPIKey = !apiKey.isEmpty

        if provider.hasStoredAPIKey != hasStoredAPIKey {
            providerStore.updateStoredAPIKeyPresence(hasStoredAPIKey, for: provider.id)
        }

        return apiKey
    }

    private func resolvedGenerationDependencies() throws -> GenerationDependencies {
        guard let provider = providerStore.defaultProvider else {
            throw AIError.providerNotConfigured
        }

        let apiKey = resolvedAPIKey(for: provider)
        guard !apiKey.isEmpty else {
            throw AIError.apiKeyMissing
        }

        let model = providerStore.effectiveDefaultModel()
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.modelNotConfigured
        }

        return GenerationDependencies(provider: provider, apiKey: apiKey, model: model)
    }
}
