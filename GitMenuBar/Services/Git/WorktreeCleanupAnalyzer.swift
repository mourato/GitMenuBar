//
//  WorktreeCleanupAnalyzer.swift
//  GitMenuBar
//

import Foundation

struct GitWorktreeAnalysisInput {
    let defaultBranchName: String
    let defaultBranchRef: String
    let currentBranchName: String?
    let currentWorktreePath: String
    let worktrees: [GitWorktreeInfo]
    let localBranches: [GitBranchReference]
    let remoteBranches: [GitBranchReference]
    let mergedLocalBranchNames: Set<String>
    let mergedRemoteBranchNames: Set<String>?
    let analysisDescription: String
    let protectedWorktreePaths: Set<String>

    init(
        defaultBranchName: String,
        defaultBranchRef: String,
        currentBranchName: String?,
        currentWorktreePath: String,
        worktrees: [GitWorktreeInfo],
        localBranches: [GitBranchReference],
        remoteBranches: [GitBranchReference],
        mergedLocalBranchNames: Set<String>,
        mergedRemoteBranchNames: Set<String>?,
        analysisDescription: String,
        protectedWorktreePaths: Set<String> = []
    ) {
        self.defaultBranchName = defaultBranchName
        self.defaultBranchRef = defaultBranchRef
        self.currentBranchName = currentBranchName
        self.currentWorktreePath = currentWorktreePath
        self.worktrees = worktrees
        self.localBranches = localBranches
        self.remoteBranches = remoteBranches
        self.mergedLocalBranchNames = mergedLocalBranchNames
        self.mergedRemoteBranchNames = mergedRemoteBranchNames
        self.analysisDescription = analysisDescription
        self.protectedWorktreePaths = Set(protectedWorktreePaths.map(Self.standardizedPath))
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

struct WorktreeCleanupAnalyzer {
    private static let protectedBranchNames: Set<String> = [
        "main",
        "master",
        "develop"
    ]

    func analyze(_ input: GitWorktreeAnalysisInput) -> GitWorktreeSnapshot {
        let worktreeByBranch: [String: String] = Dictionary(
            input.worktrees.compactMap { worktree in
                guard let branchName = worktree.branchName else {
                    return nil
                }
                return (branchName, worktree.path)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let branches = input.localBranches.map { reference in
            GitBranchCleanupInfo(
                reference: reference,
                status: branchStatus(
                    for: reference,
                    currentBranchName: input.currentBranchName,
                    worktreePath: worktreeByBranch[reference.name],
                    mergedNames: input.mergedLocalBranchNames
                ),
                worktreePath: worktreeByBranch[reference.name]
            )
        } + input.remoteBranches.map { reference in
            GitBranchCleanupInfo(
                reference: reference,
                status: branchStatus(
                    for: reference,
                    currentBranchName: nil,
                    worktreePath: nil,
                    mergedNames: input.mergedRemoteBranchNames,
                    unknownReason: "Remote default branch ref is unavailable."
                ),
                worktreePath: nil
            )
        }

        let worktrees = input.worktrees.map { worktree in
            GitWorktreeCleanupInfo(
                worktree: worktree,
                status: worktreeStatus(
                    for: worktree,
                    currentWorktreePath: input.currentWorktreePath,
                    localBranchNames: Set(input.localBranches.map(\.name)),
                    mergedLocalBranchNames: input.mergedLocalBranchNames,
                    protectedWorktreePaths: input.protectedWorktreePaths
                )
            )
        }

        let snapshot = GitWorktreeSnapshot(
            repositoryPath: input.currentWorktreePath,
            defaultBranchName: input.defaultBranchName,
            defaultBranchRef: input.defaultBranchRef,
            analysisDescription: input.analysisDescription,
            worktrees: worktrees,
            branches: branches,
            repositoryIdentity: GitRepositoryContext.normalizedPath(input.currentWorktreePath),
            protectedWorktreePaths: input.protectedWorktreePaths
        )
        return GitWorktreeSnapshot(
            repositoryPath: snapshot.repositoryPath,
            defaultBranchName: snapshot.defaultBranchName,
            defaultBranchRef: snapshot.defaultBranchRef,
            analysisDescription: snapshot.analysisDescription,
            worktrees: snapshot.worktrees,
            branches: snapshot.branches,
            repositoryIdentity: snapshot.repositoryIdentity,
            protectedWorktreePaths: snapshot.protectedWorktreePaths,
            cleanupUnits: GitCleanupUnit.build(
                repositoryIdentity: snapshot.repositoryIdentity,
                branches: snapshot.branches,
                worktrees: snapshot.worktrees
            )
        )
    }

    private func branchStatus(
        for reference: GitBranchReference,
        currentBranchName: String?,
        worktreePath: String?,
        mergedNames: Set<String>?,
        unknownReason: String = "Merge status is unavailable."
    ) -> GitBranchCleanupStatus {
        if Self.protectedBranchNames.contains(reference.name) {
            return .protected
        }
        if !reference.isRemote, reference.name == currentBranchName {
            return .current
        }
        if !reference.isRemote, let worktreePath {
            return .checkedOutElsewhere(path: worktreePath)
        }
        guard let mergedNames else {
            return .unknown(reason: unknownReason)
        }
        if mergedNames.contains(reference.name) {
            return .mergedIntoDefault
        }
        return .notMerged
    }

    private func worktreeStatus(
        for worktree: GitWorktreeInfo,
        currentWorktreePath: String,
        localBranchNames: Set<String>,
        mergedLocalBranchNames: Set<String>,
        protectedWorktreePaths: Set<String>
    ) -> GitWorktreeCleanupStatus {
        if worktree.isMainWorktree {
            return .main
        }
        if standardizedPath(worktree.path) == standardizedPath(currentWorktreePath) {
            return .current
        }
        if let reason = worktree.lockReason {
            return .locked(reason: reason)
        }
        if let reason = worktree.pruneReason {
            return .prunable(reason: reason)
        }
        switch worktree.workingTreeState {
        case .dirty:
            return .dirty
        case .unknown:
            return .unknown(reason: "Working tree status is unavailable.")
        case .clean:
            break
        }
        guard let branchName = worktree.branchName else {
            return .detached
        }
        guard localBranchNames.contains(branchName) else {
            return .unknown(reason: "Linked branch is unavailable.")
        }
        guard mergedLocalBranchNames.contains(branchName) else {
            return .branchNotMerged
        }
        if protectedWorktreePaths.contains(standardizedPath(worktree.path)) {
            return .unknown(reason: "Worktree is monitored as a project and protected from cleanup.")
        }
        return .eligible
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
