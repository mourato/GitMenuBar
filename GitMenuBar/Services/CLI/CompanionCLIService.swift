import Foundation

/// Headless orchestration for Companion CLI commands shared by the app module and `gitmenubar`.
public struct CompanionCLIService: Sendable {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case notReady(String)
        case invalidRepository(String)
        case policyRejected(String)
        case indexLocked
        case operational(String)

        public var exitCode: CompanionCLIExitCode {
            switch self {
            case .notReady:
                .notReady
            case .invalidRepository:
                .invalidRepository
            case .policyRejected:
                .policyRejected
            case .indexLocked, .operational:
                .operationalFailure
            }
        }

        public var errorDescription: String? {
            switch self {
            case let .notReady(message),
                 let .invalidRepository(message),
                 let .policyRejected(message),
                 let .operational(message):
                message
            case .indexLocked:
                "Refusing --apply because .git/index.lock exists."
            }
        }

        public var cliExitCode: Int32 {
            exitCode.rawValue
        }
    }

    public init() {}

    func makeSession(options: CompanionCLIScopeOptions) async throws -> GitMenuBarCommitSession {
        do {
            return try await GitMenuBarCommitSession(repositoryPathScope: options.repositoryPathScope)
        } catch let error as GitMenuBarCommitSessionError {
            throw Error.invalidRepository(error.localizedDescription ?? "Invalid repository.")
        }
    }

    func resolveMessage(
        session: GitMenuBarCommitSession,
        options: CompanionCLIScopeOptions
    ) async throws -> String {
        if let override = options.messageOverride {
            return try sanitizedMessage(override, policy: session.messagePolicy)
        }

        guard session.isReadyForGeneration else {
            throw Error.notReady(session.generationDisabledReason)
        }

        do {
            return try await session.generateMessage(scopeOverride: options.resolvedDiffScopeValue())
        } catch let error as AIError {
            throw mapAIError(error)
        }
    }

    func buildCommitPlan(
        session: GitMenuBarCommitSession,
        options: CompanionCLIScopeOptions
    ) async throws -> CompanionCLICommitPlan {
        let message = try await resolveMessage(session: session, options: options)
        let gitManager = session.gitManager
        await gitManager.updateUncommittedFilesAsync()

        let scope = options.resolvedDiffScopeValue()
            ?? (session.providerStore.preferences.defaultScopeMode == .stagedWithFallbackAll ? DiffScope.staged : .all)
        let files = await MainActor.run {
            filePaths(for: scope, gitManager: gitManager)
        }

        guard !files.isEmpty else {
            throw Error.operational("No changed files found for the selected scope.")
        }

        return CompanionCLICommitPlan(scope: scope, files: files, message: message)
    }

    func applyCommitPlan(
        session: GitMenuBarCommitSession,
        plan: CompanionCLICommitPlan
    ) async throws {
        try assertIndexUnlocked(at: session.repositoryPath)

        let gitManager = session.gitManager
        let result = await gitManager.commitAtomicGroupAsync(files: plan.files, message: plan.message)
        if case let .failure(error) = result {
            throw Error.operational(error.localizedDescription)
        }
    }

    func buildAtomicPlan(
        session: GitMenuBarCommitSession,
        options: CompanionCLIScopeOptions
    ) async throws -> CompanionCLIAtomicPlan {
        guard session.isReadyForGeneration else {
            throw Error.notReady(session.generationDisabledReason)
        }

        let gitManager = session.gitManager
        await gitManager.updateUncommittedFilesAsync()

        let scope = options.resolvedDiffScopeValue() ?? .unstaged
        let changedFiles = await MainActor.run {
            let paths = filePaths(for: scope, gitManager: gitManager)
            let filesByPath = Dictionary(
                (gitManager.changedFilesCLI + gitManager.stagedFilesCLI).map { ($0.path, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return paths.compactMap { filesByPath[$0] }
        }
        guard !changedFiles.isEmpty else {
            throw Error.operational("No changed files found for atomic grouping.")
        }

        let diffPerFile = await gitManager.diffForFilesAsync(files: changedFiles, scope: scope)
        let groups: [AtomicCommitGroup]
        do {
            groups = try await session.generateAtomicGroups(
                changedFiles: changedFiles,
                diffPerFile: diffPerFile
            )
        } catch let error as AIError {
            throw mapAIError(error)
        }

        guard !groups.isEmpty else {
            throw Error.operational("Atomic grouping returned no commit groups.")
        }

        return CompanionCLIAtomicPlan(groups: groups)
    }

    func applyAtomicPlan(
        session: GitMenuBarCommitSession,
        plan: CompanionCLIAtomicPlan
    ) async throws -> CompanionCLIAtomicApplyProgress? {
        let groups = plan.groups.map { AtomicCommitGroup(files: $0.files, message: $0.message) }
        return try await applyAtomicPlan(session: session, groups: groups, scope: .unstaged)
    }

    func applyAtomicPlan(
        session: GitMenuBarCommitSession,
        groups: [AtomicCommitGroup],
        scope: DiffScope = .unstaged
    ) async throws -> CompanionCLIAtomicApplyProgress? {
        try assertIndexUnlocked(at: session.repositoryPath)

        let gitManager = session.gitManager
        await gitManager.updateUncommittedFilesAsync()

        let allowedFiles = await MainActor.run {
            Set(filePaths(for: scope, gitManager: gitManager))
        }

        let plan: AtomicCommitPlan
        do {
            plan = try AtomicCommitPlan(groups: groups, allowedFiles: allowedFiles)
        } catch {
            throw Error.operational(error.localizedDescription)
        }

        var completed: [AtomicCommitGroup] = []
        for group in plan.groups {
            let result = await gitManager.commitAtomicGroupAsync(
                files: group.files,
                message: group.message,
                scope: scope
            )
            if case let .failure(error) = result {
                let remaining = Array(plan.groups.dropFirst(completed.count))
                return CompanionCLIAtomicApplyProgress(
                    error: error.localizedDescription,
                    completedGroups: completed,
                    remainingGroups: remaining
                )
            }
            completed.append(group)
        }

        return nil
    }

    func sanitizedMessage(_ message: String, policy: CommitMessagePolicy) throws -> String {
        switch policy.sanitize(message) {
        case let .success(accepted):
            return accepted
        case let .failure(error):
            throw Error.policyRejected(error.localizedDescription ?? "Commit message rejected by Message policy.")
        }
    }

    func assertIndexUnlocked(at repositoryPath: String) throws {
        let lockPath = (repositoryPath as NSString).appendingPathComponent(".git/index.lock")
        if FileManager.default.fileExists(atPath: lockPath) {
            throw Error.indexLocked
        }
    }

    @MainActor
    private func filePaths(for scope: DiffScope, gitManager: GitManager) -> [String] {
        switch scope {
        case .staged:
            return gitManager.stagedFilesCLI.map(\.path).sorted()
        case .unstaged:
            return gitManager.changedFilesCLI.map(\.path).sorted()
        case .all:
            let paths = Set(
                gitManager.stagedFilesCLI.map(\.path)
                    + gitManager.changedFilesCLI.map(\.path)
                    + gitManager.uncommittedFilesCLI
            )
            return paths.sorted()
        }
    }

    private func mapAIError(_ error: AIError) -> Error {
        switch error {
        case let .messagePolicyRejected(message):
            .policyRejected(message)
        case .providerNotConfigured, .apiKeyMissing, .modelNotConfigured:
            .notReady(error.localizedDescription ?? "CLI not ready.")
        default:
            .operational(error.localizedDescription ?? "AI request failed.")
        }
    }
}

extension GitManager {
    var changedFilesCLI: [WorkingTreeFile] {
        changedFiles
    }

    var stagedFilesCLI: [WorkingTreeFile] {
        stagedFiles
    }

    var uncommittedFilesCLI: [String] {
        uncommittedFiles
    }
}
