import Foundation

final class GitCommitHistoryService: ObservableObject {
    private static let defaultCommitHistoryLimit = 25

    @Published var commitHistory: [Commit] = []
    @Published private(set) var commitHistoryLimit = GitCommitHistoryService.defaultCommitHistoryLimit

    private let repositoryContext: GitRepositoryContext
    private let commandRunner: GitCommandRunner
    private let commitHistoryParser: CommitHistoryParser
    private var includesReflogCommitsInHistory = false

    init(repositoryContext: GitRepositoryContext, commandRunner: GitCommandRunner) {
        self.repositoryContext = repositoryContext
        self.commandRunner = commandRunner
        commitHistoryParser = CommitHistoryParser(runner: commandRunner)
    }

    private var storedRepoPath: String {
        repositoryContext.repositoryPath
    }

    private func runOnBackground<T>(_ operation: @escaping () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    private func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await GitExecution.publishOnMainActor(update)
    }

    private func executeGitCommand(
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
        let resolvedLimit = max(1, limit ?? commitHistoryLimit)
        let resolvedIncludeReflog = includeReflog ?? includesReflogCommitsInHistory
        let repositoryPath = storedRepoPath

        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
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

        await publishOnMainActor {
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
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.resolveMergeCommitStatus(for: hash)
            DispatchQueue.main.async {
                completion(result)
            }
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
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.resolveCommitPublishedStatus(for: hash)
            DispatchQueue.main.async {
                completion(result)
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
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.resolveDiffForCommit(hash)
            DispatchQueue.main.async {
                completion(result)
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

    private func resolveMergeCommitStatus(for hash: String) -> Result<Bool, Error> {
        let result = executeGitCommand(in: storedRepoPath, args: ["rev-list", "--parents", "-n", "1", hash])
        guard !result.failure else {
            return .failure(NSError(domain: "GitManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to inspect commit: \(result.output)"]))
        }

        let hashes = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)

        return .success(hashes.count > 2)
    }

    private func resolveCommitPublishedStatus(for hash: String) -> Result<Bool, Error> {
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

    private func resolveDiffForCommit(_ hash: String) -> Result<String, Error> {
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
