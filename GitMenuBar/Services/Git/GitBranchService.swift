//
//  GitBranchService.swift
//  GitMenuBar
//

import Combine
import Foundation

/// Owns branch-management state and git operations, extracted from `GitManager`
/// to keep that facade focused. `GitManager` pipes the published branch state
/// back to its own public facade so call sites are unchanged.
///
/// Threading mirrors `GitManager`: heavy git work runs on a background queue and
/// published state is written on the main thread via `DispatchQueue.main.async`
/// / `MainActor.run`, so the class itself is not actor-isolated.
final class GitBranchService: ObservableObject {
    @Published var currentBranch: String = "main"
    @Published var isAheadOfRemote: Bool = false
    @Published var remoteBranchName: String = ""
    @Published var behindCount: Int = 0
    @Published var isBehindRemote: Bool = false
    @Published var isRemoteAhead: Bool = false
    @Published var availableBranches: [String] = []
    @Published var branchInfos: [BranchInfo] = []
    @Published var defaultBranchName: String = "main"
    @Published var currentHash: String = ""
    @Published var isDetachedHead: Bool = false
    @Published var lastActiveBranch: String = ""

    private let repositoryContext: GitRepositoryContext
    private let commandRunner: GitCommandRunner

    /// Injected by `GitManager` so branch mutations can trigger a full app
    /// refresh (commit history, working tree, …) which lives outside this service.
    var refreshHandler: (@escaping () -> Void) -> Void

    init(repositoryContext: GitRepositoryContext, commandRunner: GitCommandRunner) {
        self.repositoryContext = repositoryContext
        self.commandRunner = commandRunner
        refreshHandler = { _ in }
    }

    var storedRepoPath: String {
        repositoryContext.repositoryPath
    }

    func runOnBackground<T>(_ operation: @escaping () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await GitExecution.publishOnMainActor(update)
    }

    func executeGitCommand(
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
