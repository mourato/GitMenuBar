import Foundation

enum GitMenuBarCommitSessionError: Error, Equatable, LocalizedError {
    case notADirectory(String)
    case notAGitRepository(String)

    var errorDescription: String? {
        switch self {
        case let .notADirectory(path):
            "Repository path scope is not a directory: \(path)"
        case let .notAGitRepository(path):
            "Repository path scope is not inside a git work tree: \(path)"
        }
    }
}

/// Non-UI session for Companion CLI and other headless callers.
///
/// Resolves **Repository path scope** to a git root, loads shared AI stores,
/// and delegates generation to existing services that enforce **Message policy**.
///
/// **Concurrency and ownership:** One session instance owns one Companion CLI
/// process lifetime. Do not share a session with SwiftUI views, `@Published`
/// observers, or the menu bar app's main-actor coordinators — construct a
/// dedicated session per CLI invocation instead. This type is intentionally
/// not `@MainActor`-isolated because it is CLI-oriented and may perform
/// blocking Git and network work off the main thread.
final class GitMenuBarCommitSession {
    private struct GenerationDependencies {
        let provider: AIProviderConfig
        let apiKey: String
        let model: String
    }

    let repositoryPath: String
    /// Shared Message policy applied by nested AI services; exposed for CLI `--message` sanitization.
    let messagePolicy: CommitMessagePolicy

    private let keychainStore: any AIAPIKeyStore
    private let messageService: AICommitMessageService
    private let grouper: AICommitGrouperService

    /// Shared with Companion CLI within the same module.
    let providerStore: AIProviderStore
    let gitManager: GitManager

    init(
        repositoryPathScope: String,
        providerStore: AIProviderStore = AIProviderStore(),
        keychainStore: any AIAPIKeyStore = AIKeychainStore(service: "com.mourato.GitMenuBar"),
        messagePolicy: CommitMessagePolicy = .shared,
        messageService: AICommitMessageService? = nil,
        commandRunner: GitCommandRunner = GitCommandRunner(),
        grouper: AICommitGrouperService? = nil
    ) async throws {
        let resolvedPath = try Self.resolveGitRoot(from: repositoryPathScope, using: commandRunner)
        repositoryPath = resolvedPath
        self.providerStore = providerStore
        self.keychainStore = keychainStore
        self.messagePolicy = messagePolicy
        let resolvedMessageService = messageService ?? AICommitMessageService(messagePolicy: messagePolicy)
        self.messageService = resolvedMessageService
        gitManager = await MainActor.run {
            GitManager(repositoryPathOverride: resolvedPath)
        }
        self.grouper = grouper ?? AICommitGrouperService(aiService: resolvedMessageService, messagePolicy: messagePolicy)
    }

    init(
        repositoryPath: String,
        providerStore: AIProviderStore,
        keychainStore: any AIAPIKeyStore,
        messagePolicy: CommitMessagePolicy = .shared,
        messageService: AICommitMessageService? = nil,
        grouper: AICommitGrouperService? = nil
    ) async {
        self.repositoryPath = repositoryPath
        self.providerStore = providerStore
        self.keychainStore = keychainStore
        self.messagePolicy = messagePolicy
        let resolvedMessageService = messageService ?? AICommitMessageService(messagePolicy: messagePolicy)
        self.messageService = resolvedMessageService
        let resolvedPath = repositoryPath
        gitManager = await MainActor.run {
            GitManager(repositoryPathOverride: resolvedPath)
        }
        self.grouper = grouper ?? AICommitGrouperService(aiService: resolvedMessageService, messagePolicy: messagePolicy)
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
        return try await messageService.generateCommitMessage(
            request: AICommitMessageService.GenerationRequest(
                provider: dependencies.provider,
                apiKey: dependencies.apiKey,
                model: dependencies.model,
                preferredScopeMode: providerStore.preferences.defaultScopeMode,
                overrideScope: scopeOverride,
                gitManager: gitManager
            )
        )
    }

    func generateMessage(
        forRawDiff rawDiff: String,
        scopeDescription: String = "Selected commit"
    ) async throws -> String {
        let dependencies = try resolvedGenerationDependencies()
        return try await messageService.generateCommitMessage(
            provider: dependencies.provider,
            apiKey: dependencies.apiKey,
            model: dependencies.model,
            rawDiff: rawDiff,
            scopeDescription: scopeDescription
        )
    }

    func generateAtomicGroups(
        changedFiles: [WorkingTreeFile],
        diffPerFile: [String: String]
    ) async throws -> [AtomicCommitGroup] {
        let dependencies = try resolvedGenerationDependencies()
        return try await grouper.generateAtomicGroups(
            changedFiles: changedFiles,
            diffPerFile: diffPerFile,
            provider: dependencies.provider,
            apiKey: dependencies.apiKey,
            model: dependencies.model
        )
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

        let workingDirectory: String = if isDirectory.boolValue {
            expanded
        } else {
            (expanded as NSString).deletingLastPathComponent
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
