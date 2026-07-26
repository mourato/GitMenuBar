import Foundation

enum GitMenuBarCommitSessionError: Error, Equatable, LocalizedError {
    case notADirectory(String)
    case notAGitRepository(String)

    var errorDescription: String? {
        switch self {
        case let .notADirectory(path):
            return "Repository path scope is not a directory: \(path)"
        case let .notAGitRepository(path):
            return "Repository path scope is not inside a git work tree: \(path)"
        }
    }
}

/// Non-UI session for Companion CLI and other headless callers.
///
/// Resolves **Repository path scope** to a git root, loads shared AI stores,
/// and delegates generation to existing services while enforcing **Message policy**.
final class GitMenuBarCommitSession: @unchecked Sendable {
    private struct GenerationDependencies {
        let provider: AIProviderConfig
        let apiKey: String
        let model: String
    }

    let repositoryPath: String

    private let providerStore: AIProviderStore
    private let keychainStore: any AIAPIKeyStore
    private let messageService: AICommitMessageService
    private let gitManager: GitManager
    private let grouper: AICommitGrouperService
    private let messagePolicy: CommitMessagePolicy

    init(
        repositoryPathScope: String,
        providerStore: AIProviderStore = AIProviderStore(),
        keychainStore: any AIAPIKeyStore = AIKeychainStore(service: "com.mourato.GitMenuBar"),
        messageService: AICommitMessageService = AICommitMessageService(),
        messagePolicy: CommitMessagePolicy = .shared,
        commandRunner: GitCommandRunner = GitCommandRunner()
    ) throws {
        repositoryPath = try Self.resolveGitRoot(from: repositoryPathScope, using: commandRunner)
        self.providerStore = providerStore
        self.keychainStore = keychainStore
        self.messageService = messageService
        self.messagePolicy = messagePolicy
        gitManager = GitManager(repositoryPathOverride: repositoryPath)
        grouper = AICommitGrouperService(aiService: messageService)
    }

    init(
        repositoryPath: String,
        providerStore: AIProviderStore,
        keychainStore: any AIAPIKeyStore,
        messageService: AICommitMessageService,
        messagePolicy: CommitMessagePolicy = .shared
    ) {
        self.repositoryPath = repositoryPath
        self.providerStore = providerStore
        self.keychainStore = keychainStore
        self.messageService = messageService
        self.messagePolicy = messagePolicy
        gitManager = GitManager(repositoryPathOverride: repositoryPath)
        grouper = AICommitGrouperService(aiService: messageService)
    }

    var isReadyForGeneration: Bool {
        guard let provider = providerStore.defaultProvider else {
            return false
        }

        let hasAPIKey = !resolvedAPIKey(for: provider).isEmpty
        let hasModel = !providerStore.effectiveDefaultModel()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        return hasAPIKey && hasModel
    }

    var generationDisabledReason: String {
        guard let provider = providerStore.defaultProvider else {
            return "Configure at least one AI provider in Settings to enable commit generation."
        }

        if resolvedAPIKey(for: provider).isEmpty {
            return "Add an API key for the default provider in Settings to enable commit generation."
        }

        let hasModel = !providerStore.effectiveDefaultModel()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        if !hasModel {
            return "Choose a default model in Settings to enable commit generation."
        }

        return ""
    }

    func generateMessage(scopeOverride: DiffScope?) async throws -> String {
        let dependencies = try resolvedGenerationDependencies()
        let message = try await messageService.generateCommitMessage(
            request: AICommitMessageService.GenerationRequest(
                provider: dependencies.provider,
                apiKey: dependencies.apiKey,
                model: dependencies.model,
                preferredScopeMode: providerStore.preferences.defaultScopeMode,
                overrideScope: scopeOverride,
                gitManager: gitManager
            )
        )
        return try applyMessagePolicy(message)
    }

    func generateMessage(
        forRawDiff rawDiff: String,
        scopeDescription: String = "Selected commit"
    ) async throws -> String {
        let dependencies = try resolvedGenerationDependencies()
        let message = try await messageService.generateCommitMessage(
            provider: dependencies.provider,
            apiKey: dependencies.apiKey,
            model: dependencies.model,
            rawDiff: rawDiff,
            scopeDescription: scopeDescription
        )
        return try applyMessagePolicy(message)
    }

    func generateAtomicGroups(
        changedFiles: [WorkingTreeFile],
        diffPerFile: [String: String]
    ) async throws -> [AtomicCommitGroup] {
        let dependencies = try resolvedGenerationDependencies()
        let groups = try await grouper.generateAtomicGroups(
            changedFiles: changedFiles,
            diffPerFile: diffPerFile,
            provider: dependencies.provider,
            apiKey: dependencies.apiKey,
            model: dependencies.model
        )
        return try groups.map { group in
            var sanitizedGroup = group
            sanitizedGroup.message = try applyMessagePolicy(group.message)
            return sanitizedGroup
        }
    }

    static func resolveGitRoot(
        from repositoryPathScope: String,
        using commandRunner: GitCommandRunner
    ) throws -> String {
        let expanded = (repositoryPathScope as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
            throw GitMenuBarCommitSessionError.notADirectory(expanded)
        }

        let workingDirectory: String
        if isDirectory.boolValue {
            workingDirectory = expanded
        } else {
            workingDirectory = (expanded as NSString).deletingLastPathComponent
        }

        let result = GitExecution.executeGitCommand(
            in: workingDirectory,
            args: ["rev-parse", "--show-toplevel"],
            using: commandRunner
        )

        guard !result.failure else {
            throw GitMenuBarCommitSessionError.notAGitRepository(workingDirectory)
        }

        let root = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else {
            throw GitMenuBarCommitSessionError.notAGitRepository(workingDirectory)
        }

        return URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.path
    }

    private func applyMessagePolicy(_ message: String) throws -> String {
        switch messagePolicy.sanitize(message) {
        case let .success(accepted):
            return accepted
        case let .failure(error):
            throw error.aiError
        }
    }

    private func resolvedAPIKey(for provider: AIProviderConfig) -> String {
        let apiKey = keychainStore.apiKey(for: provider.id)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
