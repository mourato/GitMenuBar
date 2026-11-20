import Combine
import Foundation
import Observation

@MainActor
@Observable
final class GitBranchService {
    var currentBranch: String = "main"
    var isAheadOfRemote: Bool = false
    var remoteBranchName: String = ""
    var behindCount: Int = 0
    var isBehindRemote: Bool = false
    var isRemoteAhead: Bool = false
    var availableBranches: [String] = []
    var branchInfos: [BranchInfo] = []
    var defaultBranchName: String = "main"
    var currentHash: String = ""
    var isDetachedHead: Bool = false
    var lastActiveBranch: String = ""
    var worktreeSnapshot: GitWorktreeSnapshot?
    var cleanupProgress: GitCleanupProgress?

    @ObservationIgnored var cleanupProgressGeneration = 0
    private nonisolated(unsafe) let repositoryContext: GitRepositoryContext
    nonisolated(unsafe) let commandRunner: GitCommandRunner

    @ObservationIgnored var refreshHandler: (@escaping () -> Void) -> Void

    init(repositoryContext: GitRepositoryContext, commandRunner: GitCommandRunner) {
        self.repositoryContext = repositoryContext
        self.commandRunner = commandRunner
        refreshHandler = { _ in }
    }

    var storedRepoPath: String {
        repositoryContext.repositoryPath
    }

    func runOnBackground<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await GitExecution.publishOnMainActor(update)
    }

    nonisolated func executeGitCommand(
        in directory: String,
        args: [String]
    ) -> (output: String, failure: Bool) {
        GitExecution.executeGitCommand(
            in: directory,
            args: args,
            using: commandRunner
        )
    }
}
