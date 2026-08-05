import Foundation

@MainActor
final class GitCommitHistoryService: ObservableObject {
    private static let defaultCommitHistoryLimit = 25

    @Published var commitHistory: [Commit] = []
    @Published private(set) var commitHistoryLimit = GitCommitHistoryService.defaultCommitHistoryLimit

    private nonisolated(unsafe) let repositoryContext: GitRepositoryContext
    private let commandRunner: GitCommandRunner
    private nonisolated(unsafe) let commitHistoryParser: CommitHistoryParser
    private var includesReflogCommitsInHistory = false

    init(repositoryContext: GitRepositoryContext, commandRunner: GitCommandRunner) {
        self.repositoryContext = repositoryContext
        self.commandRunner = commandRunner
        commitHistoryParser = CommitHistoryParser(runner: commandRunner)
    }

    private nonisolated var storedRepoPath: String {
        repositoryContext.repositoryPath
    }

    private func runOnBackground<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    private func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await GitExecution.publishOnMainActor(update)
    }

    private nonisolated func executeGitCommand(
        in directory: String,
        args: [String],
        useAuth: Bool = false,
        additionalEnvironment: [String: String] = [:]
    ) -> (output: String, failure: Bool) {
        GitExecution.executeGitCommand(
            in: directory,
            args: args,
            useAuth: useAuth,
            additionalEnvironment: additionalEnvironment,
            using: commandRunner
        )
    }

    private func makeMissingRepositoryError() -> NSError {
        GitExecution.missingRepositoryError()
    }

    var canLoadMoreCommitHistory: Bool {
        !commitHistory.isEmpty && commitHistory.count >= commitHistoryLimit
    }

    func fetchCommitHistory(limit: Int? = nil, includeReflog: Bool? = nil) {
        let resolvedLimit = max(1, limit ?? commitHistoryLimit)
        let resolvedIncludeReflog = includeReflog ?? includesReflogCommitsInHistory

        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.includesReflogCommitsInHistory = resolvedIncludeReflog
                self.commitHistoryLimit = resolvedLimit
                self.commitHistory = []
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let commits = self.commitHistoryParser.fetchCommitHistory(
                in: self.storedRepoPath,
                limit: resolvedLimit,
                includeReflog: resolvedIncludeReflog
            )

            DispatchQueue.main.async {
                self.includesReflogCommitsInHistory = resolvedIncludeReflog
                self.commitHistoryLimit = resolvedLimit
                self.commitHistory = commits
            }
        }
    }

    func fetchCommitHistoryAsync(limit: Int? = nil, includeReflog: Bool? = nil) async {
        await fetchCommitHistoryAsync(limit: limit, includeReflog: includeReflog, session: nil)
    }

    func fetchCommitHistoryAsync(
        limit: Int? = nil,
        includeReflog: Bool? = nil,
        session: GitRefreshSession?
    ) async {
        let resolvedLimit = max(1, limit ?? commitHistoryLimit)
        let resolvedIncludeReflog = includeReflog ?? includesReflogCommitsInHistory
        let repositoryPath = session?.repositoryPath ?? storedRepoPath

        guard !repositoryPath.isEmpty else {
            await GitExecution.publishOnMainActor(ifCurrent: session) {
                self.includesReflogCommitsInHistory = resolvedIncludeReflog
                self.commitHistoryLimit = resolvedLimit
                self.commitHistory = []
            }
            return
        }

        let commits = await runOnBackground {
            self.commitHistoryParser.fetchCommitHistory(
                in: repositoryPath,
                limit: resolvedLimit,
                includeReflog: resolvedIncludeReflog
            )
        }

        await GitExecution.publishOnMainActor(ifCurrent: session) {
            self.includesReflogCommitsInHistory = resolvedIncludeReflog
            self.commitHistoryLimit = resolvedLimit
            self.commitHistory = commits
        }
    }

    func loadMoreCommitHistory(batchSize: Int = GitCommitHistoryService.defaultCommitHistoryLimit) {
        let nextLimit = commitHistoryLimit + max(1, batchSize)
        fetchCommitHistory(limit: nextLimit)
    }

    func isMergeCommit(_ hash: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        Task {
            let result = await checkIsMergeCommitAsync(hash)
            completion(result)
        }
    }

    func checkIsMergeCommitAsync(_ hash: String) async -> Result<Bool, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"]))
        }

        return await runOnBackground {
            self.resolveMergeCommitStatus(for: hash)
        }
    }

    func isCommitPublishedToUpstream(_ hash: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        Task {
            do {
                let result = try await isCommitPublishedToUpstreamAsync(hash)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func isCommitPublishedToUpstreamAsync(_ hash: String) async throws -> Bool {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            throw makeMissingRepositoryError()
        }

        let result = await runOnBackground {
            self.resolveCommitPublishedStatus(for: hash)
        }

        switch result {
        case let .success(isPublished):
            return isPublished
        case let .failure(error):
            throw error
        }
    }

    func diffForCommit(_ hash: String, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let result = try await diffForCommitAsync(hash)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func diffForCommitAsync(_ hash: String) async throws -> String {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            throw makeMissingRepositoryError()
        }

        let result = await runOnBackground {
            self.resolveDiffForCommit(hash)
        }

        switch result {
        case let .success(diff):
            return diff
        case let .failure(error):
            throw error
        }
    }

    // MARK: - Private Helpers

    private nonisolated func resolveMergeCommitStatus(for hash: String) -> Result<Bool, Error> {
        let result = executeGitCommand(in: storedRepoPath, args: ["rev-list", "--parents", "-n", "1", hash])
        guard !result.failure else {
            return .failure(NSError(domain: "GitManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to inspect commit: \(result.output)"]))
        }

        let hashes = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)

        return .success(hashes.count > 2)
    }

    private nonisolated func resolveCommitPublishedStatus(for hash: String) -> Result<Bool, Error> {
        let upstreamResult = executeGitCommand(in: storedRepoPath, args: ["rev-parse", "--verify", "@{u}"])
        if upstreamResult.failure {
            return .success(false)
        }

        let containsResult = executeGitCommand(
            in: storedRepoPath,
            args: ["merge-base", "--is-ancestor", hash, "@{u}"]
        )

        return .success(!containsResult.failure)
    }

    private nonisolated func resolveDiffForCommit(_ hash: String) -> Result<String, Error> {
        let result = executeGitCommand(
            in: storedRepoPath,
            args: ["show", "--format=", "--no-renames", "--no-ext-diff", hash]
        )

        guard !result.failure else {
            return .failure(NSError(domain: "GitManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to load commit diff: \(result.output)"]))
        }

        let diff = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diff.isEmpty else {
            return .failure(NSError(domain: "GitManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "No diff found for the selected commit."]))
        }

        return .success(diff)
    }
}
