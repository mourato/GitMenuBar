import Foundation

@MainActor
final class AICommitCoordinator: ObservableObject {
    private struct GenerationDependencies {
        let configuration: AICommitGenerationConfiguration
    }

    @Published private(set) var isGenerating: Bool = false
    @Published var generationError: String?
    @Published private(set) var automaticRetryAvailable = false

    private let providerStore: AIProviderStore
    private let keychainStore: any AIAPIKeyStore
    private let messageService: AICommitMessageService
    private let gitManager: GitManager
    private let grouper: AICommitGrouperService
    private let chatGPTSubscription: ChatGPTSubscriptionManager?
    private var messageGenerationFailureCount = 0

    init(
        providerStore: AIProviderStore,
        keychainStore: any AIAPIKeyStore,
        messageService: AICommitMessageService,
        gitManager: GitManager,
        chatGPTSubscription: ChatGPTSubscriptionManager? = nil
    ) {
        self.providerStore = providerStore
        self.keychainStore = keychainStore
        self.messageService = messageService
        self.gitManager = gitManager
        self.chatGPTSubscription = chatGPTSubscription
        grouper = AICommitGrouperService(aiService: messageService)
    }

    func generateMessage(scopeOverride: DiffScope?) async throws -> String {
        beginMessageGeneration()

        let dependencies: GenerationDependencies
        do {
            dependencies = try resolvedGenerationDependencies()
        } catch {
            recordMessageGenerationFailure(error, allowsAutomaticRetry: true)
            throw error
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await messageService.generateCommitMessage(
                request: AICommitMessageService.GenerationRequest(
                    generation: dependencies.configuration,
                    preferredScopeMode: providerStore.preferences.defaultScopeMode,
                    overrideScope: scopeOverride,
                    gitManager: gitManager
                )
            )
        } catch {
            recordMessageGenerationFailure(error, allowsAutomaticRetry: true)
            throw error
        }
    }

    func generateMessageUsingFallback(scopeOverride: DiffScope?) async throws -> String {
        beginMessageGeneration()

        let dependencies: GenerationDependencies
        do {
            dependencies = try resolvedGenerationDependencies(isFallback: true)
        } catch {
            recordMessageGenerationFailure(error, allowsAutomaticRetry: false)
            throw error
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await messageService.generateCommitMessage(
                request: AICommitMessageService.GenerationRequest(
                    generation: dependencies.configuration,
                    preferredScopeMode: providerStore.preferences.defaultScopeMode,
                    overrideScope: scopeOverride,
                    gitManager: gitManager
                )
            )
        } catch {
            recordMessageGenerationFailure(error, allowsAutomaticRetry: false)
            throw error
        }
    }

    func generateMessage(
        forRawDiff rawDiff: String,
        scopeDescription: String = "Selected commit"
    ) async throws -> String {
        resetGenerationState()

        let dependencies = try resolvedGenerationDependencies()

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await messageService.generateCommitMessage(
                generation: dependencies.configuration,
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

    func generateAtomicGroups(
        changedFiles: [WorkingTreeFile],
        diffPerFile: [String: String]
    ) async throws -> [AtomicCommitGroup] {
        resetGenerationState()
        let dependencies = try resolvedGenerationDependencies()

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await grouper.generateAtomicGroups(
                changedFiles: changedFiles,
                diffPerFile: diffPerFile,
                generation: dependencies.configuration
            )
        } catch {
            generationError = error.localizedDescription
            throw error
        }
    }

    func generateAtomicHunkGroups(snapshot: AtomicCommitSnapshot) async throws -> [AtomicCommitGroup] {
        resetGenerationState()
        let dependencies = try resolvedGenerationDependencies()
        isGenerating = true
        defer { isGenerating = false }
        do {
            return try await grouper.generateAtomicHunkGroups(
                snapshot: snapshot,
                generation: dependencies.configuration
            )
        } catch {
            generationError = error.localizedDescription
            throw error
        }
    }

    func apiKey(for providerId: UUID) -> String {
        guard let provider = providerStore.providers.first(where: { $0.id == providerId }) else { return "" }
        let apiKey: String
        do {
            apiKey = try keychainStore.apiKey(for: AIProviderCredentialID(provider: provider)) ?? ""
        } catch {
            return ""
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providerStore.updateStoredAPIKeyPresence(false, for: providerId)
        }
        return apiKey
    }

    func consumeAutomaticRetry() {
        automaticRetryAvailable = false
    }

    func resetGenerationState() {
        generationError = nil
        automaticRetryAvailable = false
        messageGenerationFailureCount = 0
    }

    @discardableResult
    func saveAPIKey(_ apiKey: String, for providerId: UUID) -> Result<Void, Error> {
        guard let provider = providerStore.providers.first(where: { $0.id == providerId }) else {
            return .failure(AIError.providerNotConfigured)
        }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try keychainStore.deleteAPIKey(for: AIProviderCredentialID(provider: provider))
                providerStore.updateStoredAPIKeyPresence(false, for: providerId)
            } else {
                try keychainStore.saveAPIKey(trimmed, for: AIProviderCredentialID(provider: provider))
                providerStore.updateStoredAPIKeyPresence(true, for: providerId)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    @discardableResult
    func deleteAPIKey(for providerId: UUID) -> Result<Void, Error> {
        guard let provider = providerStore.providers.first(where: { $0.id == providerId }) else {
            return .failure(AIError.providerNotConfigured)
        }
        do {
            try keychainStore.deleteAPIKey(for: AIProviderCredentialID(provider: provider))
            providerStore.updateStoredAPIKeyPresence(false, for: providerId)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    var isReadyForGeneration: Bool {
        if providerStore.preferences.defaultUsesChatGPT {
            guard providerStore.preferences.chatGPTEnabled,
                  let chatGPTSubscription,
                  chatGPTSubscription.isConnected else { return false }
            let model = providerStore.effectiveDefaultModel()
            return !model.isEmpty && chatGPTSubscription.models.contains { $0.id == model }
        }

        guard let provider = providerStore.defaultProvider else {
            return false
        }

        let hasAPIKey = provider.hasStoredAPIKey
        let hasModel = !providerStore.effectiveDefaultModel().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return hasAPIKey && hasModel
    }

    var generationDisabledReason: String {
        if providerStore.preferences.defaultUsesChatGPT {
            guard providerStore.preferences.chatGPTEnabled else {
                return AIError.chatGPTDisabled.localizedDescription
            }
            guard let chatGPTSubscription else {
                return AIError.chatGPTUnavailable.localizedDescription
            }
            if case let .unavailable(message) = chatGPTSubscription.phase {
                return message
            }
            if case let .failed(message) = chatGPTSubscription.phase {
                return message
            }
            if chatGPTSubscription.phase == .signedOut {
                return AIError.chatGPTUnavailable.localizedDescription
            }
            let model = providerStore.effectiveDefaultModel()
            if model.isEmpty || !chatGPTSubscription.models.contains(where: { $0.id == model }) {
                return "Choose a model offered by your ChatGPT subscription in Settings."
            }
            return ""
        }

        guard let provider = providerStore.defaultProvider else {
            return "Configure at least one AI provider in Settings to enable commit generation."
        }

        if !provider.hasStoredAPIKey {
            return "Add an API key for the default provider in Settings to enable commit generation."
        }

        let hasModel = !providerStore.effectiveDefaultModel().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasModel {
            return "Choose a default model in Settings to enable commit generation."
        }

        return ""
    }

    var isReadyForFallbackGeneration: Bool {
        if providerStore.usesChatGPTForFallback {
            guard providerStore.preferences.chatGPTEnabled,
                  let chatGPTSubscription,
                  chatGPTSubscription.isConnected else { return false }
            let model = providerStore.effectiveFallbackModel()
            return !model.isEmpty && chatGPTSubscription.models.contains { $0.id == model }
        }

        guard let provider = providerStore.fallbackProvider else {
            return false
        }

        return provider.hasStoredAPIKey
            && !providerStore.effectiveFallbackModel().isEmpty
    }

    private func resolvedAPIKey(for provider: AIProviderConfig) -> String {
        let apiKey: String
        do {
            apiKey = try (keychainStore.apiKey(for: AIProviderCredentialID(provider: provider)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
        let hasStoredAPIKey = !apiKey.isEmpty

        if provider.hasStoredAPIKey != hasStoredAPIKey {
            providerStore.updateStoredAPIKeyPresence(hasStoredAPIKey, for: provider.id)
        }

        return apiKey
    }

    private func resolvedGenerationDependencies(
        isFallback: Bool = false
    ) throws -> GenerationDependencies {
        let usesChatGPT = isFallback ? providerStore.usesChatGPTForFallback : providerStore.preferences.defaultUsesChatGPT
        let model = isFallback ? providerStore.effectiveFallbackModel() : providerStore.effectiveDefaultModel()
        let modelError: AIError = isFallback ? .fallbackModelNotConfigured : .modelNotConfigured

        if usesChatGPT {
            guard providerStore.preferences.chatGPTEnabled else {
                throw AIError.chatGPTDisabled
            }
            guard chatGPTSubscription != nil else {
                throw AIError.chatGPTUnavailable
            }
            guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw modelError
            }
            return GenerationDependencies(configuration: .chatGPT(
                model: model,
                reasoningEffort: providerStore.chatGPTReasoningEffort(for: model)
            ))
        }

        guard let provider = isFallback ? providerStore.fallbackProvider : providerStore.defaultProvider else {
            throw AIError.providerNotConfigured
        }
        let apiKey = resolvedAPIKey(for: provider)
        guard !apiKey.isEmpty else {
            throw AIError.apiKeyMissing
        }

        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw modelError
        }

        return GenerationDependencies(configuration: .api(
            provider: provider,
            apiKey: apiKey,
            model: model
        ))
    }

    private func beginMessageGeneration() {
        if generationError == nil {
            messageGenerationFailureCount = 0
        }
        generationError = nil
        automaticRetryAvailable = false
    }

    private func recordMessageGenerationFailure(_ error: Error, allowsAutomaticRetry: Bool) {
        messageGenerationFailureCount += 1
        generationError = error.localizedDescription
        automaticRetryAvailable = allowsAutomaticRetry && messageGenerationFailureCount == 1
    }
}
