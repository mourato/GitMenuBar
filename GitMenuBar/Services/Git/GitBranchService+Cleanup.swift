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
        cleanupProgressGeneration += 1
        let progressGeneration = cleanupProgressGeneration
        cleanupProgress = .init(
            completed: 0,
            total: units.count,
            projectName: URL(fileURLWithPath: repositoryPath).lastPathComponent,
            detail: "Preparing cleanup"
        )
        let progressHandler = cleanupProgressHandler(for: progressGeneration)
        let result = await runOnBackground {
            GitCleanupRepository(runner: self.commandRunner).cleanup(
                units: units,
                snapshot: snapshot,
                repositoryPath: repositoryPath,
                projectName: URL(fileURLWithPath: repositoryPath).lastPathComponent,
                progress: progressHandler
            )
        }
        cleanupProgress = nil
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
        cleanupProgressGeneration += 1
        let progressGeneration = cleanupProgressGeneration
        cleanupProgress = .init(
            completed: 0,
            total: targets.count,
            projectName: URL(fileURLWithPath: repositoryPath).lastPathComponent,
            detail: "Preparing cleanup"
        )
        let progressHandler = cleanupProgressHandler(for: progressGeneration)
        let result = await runOnBackground {
            GitCleanupRepository(runner: self.commandRunner).cleanup(
                targets: targets,
                snapshot: snapshot,
                repositoryPath: repositoryPath,
                projectName: URL(fileURLWithPath: repositoryPath).lastPathComponent,
                progress: progressHandler
            )
        }
        cleanupProgress = nil
        if !targets.isEmpty {
            refreshHandler {}
        }
        return .success(result)
    }

    private func cleanupProgressHandler(for generation: Int) -> @Sendable (GitCleanupProgress) -> Void {
        { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, cleanupProgressGeneration == generation else { return }
                cleanupProgress = progress
            }
        }
    }

    private nonisolated func cleanupError(_ description: String) -> NSError {
        NSError(domain: "GitManager", code: 70, userInfo: [NSLocalizedDescriptionKey: description])
    }
}
