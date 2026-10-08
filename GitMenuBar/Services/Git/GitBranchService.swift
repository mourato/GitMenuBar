//
//  GitBranchService.swift
//  GitMenuBar
//

import Combine
import Foundation
import Observation

/// Owns branch-management state and git operations, extracted from `GitManager`
/// to keep that facade focused. `GitManager` pipes the published branch state
/// back to its own public facade so call sites are unchanged.
///
/// Threading mirrors `GitManager`: heavy git work runs on a background queue and
/// published state is written on the main thread via `Task { @MainActor in }`.
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

    /// Injected by `GitManager` so branch mutations can trigger a full app
    /// refresh (commit history, working tree, …) which lives outside this service.
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
        args: [String],
        useAuth: Bool = false
    ) -> (output: String, failure: Bool) {
        GitExecution.executeGitCommand(
            in: directory,
            args: args,
            useAuth: useAuth,
            using: commandRunner
        )
    }
}
