import Foundation

extension GitBranchService {
    func resolveWorktreeSnapshotAsync() async -> Result<GitWorktreeSnapshot, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return .failure(GitExecution.missingRepositoryError()) }
        let defaultBranchName = await getDefaultBranchNameAsync()
        let protectedPaths = Set(MonitoredProjectsStore().monitoredProjects().map(\.path))
        let result = await runOnBackground {
            GitCleanupRepository(runner: self.commandRunner).analyze(
                repositoryPath: repositoryPath,
                defaultBranchName: defaultBranchName,
                protectedWorktreePaths: protectedPaths
            )
        }
        if case let .success(analysis) = result {
            await publishOnMainActor { self.worktreeSnapshot = analysis.snapshot }
            return .success(analysis.snapshot)
        }
        if case let .failure(error) = result {
            return .failure(error)
        }
        return .failure(GitExecution.missingRepositoryError())
    }
}
