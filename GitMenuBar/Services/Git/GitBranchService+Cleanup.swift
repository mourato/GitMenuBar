import Foundation

extension GitBranchService {
    func performCleanupAsync(
        units: [GitCleanupUnit],
        snapshot: GitWorktreeSnapshot
    ) async -> Result<GitCleanupBatchResult, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return .failure(GitExecution.missingRepositoryError()) }
        guard GitRepositoryContext.normalizedPath(repositoryPath) == GitRepositoryContext.normalizedPath(snapshot.repositoryPath) else {
            return .failure(cleanupError("The repository changed before cleanup started. Reload and try again."))
        }
        let result = await runOnBackground {
            GitCleanupRepository(runner: self.commandRunner).cleanup(
                units: units,
                snapshot: snapshot,
                repositoryPath: repositoryPath
            )
        }
        if !units.isEmpty {
            refreshHandler {}
        }
        return .success(result)
    }

    func performCleanupAsync(
        targets: [GitCleanupTarget],
        snapshot: GitWorktreeSnapshot
    ) async -> Result<GitCleanupBatchResult, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return .failure(GitExecution.missingRepositoryError()) }
        guard GitRepositoryContext.normalizedPath(repositoryPath) == GitRepositoryContext.normalizedPath(snapshot.repositoryPath) else {
            return .failure(cleanupError("The repository changed before cleanup started. Reload and try again."))
        }
        let result = await runOnBackground {
            GitCleanupRepository(runner: self.commandRunner).cleanup(
                targets: targets,
                snapshot: snapshot,
                repositoryPath: repositoryPath
            )
        }
        if !targets.isEmpty {
            refreshHandler {}
        }
        return .success(result)
    }

    private nonisolated func cleanupError(_ description: String) -> NSError {
        NSError(domain: "GitManager", code: 70, userInfo: [NSLocalizedDescriptionKey: description])
    }
}
