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
    let mergedRemoteBranchNamesByRemote: [String: Set<String>]?
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
        protectedWorktreePaths: Set<String> = [],
        mergedRemoteBranchNamesByRemote: [String: Set<String>]? = nil
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
        self.mergedRemoteBranchNamesByRemote = mergedRemoteBranchNamesByRemote
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

    func analyze(_ input: GitWorktreeAnalysisInput, repositoryIdentity: String? = nil) -> GitWorktreeSnapshot {
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
                    defaultBranchName: input.defaultBranchName,
                    currentBranchName: input.currentBranchName,
                    worktreePath: worktreeByBranch[reference.name],
                    mergedNames: input.mergedLocalBranchNames
                ),
                worktreePath: worktreeByBranch[reference.name],
                isMergedIntoDefaultHint: input.mergedLocalBranchNames.contains(reference.name)
            )
        } + input.remoteBranches.map { reference in
            let mergedNames = input.mergedRemoteBranchNamesByRemote?[reference.remoteName ?? "origin"]
                ?? input.mergedRemoteBranchNames
            return GitBranchCleanupInfo(
                reference: reference,
                status: branchStatus(
                    for: reference,
                    defaultBranchName: input.defaultBranchName,
                    currentBranchName: nil,
                    worktreePath: nil,
                    mergedNames: mergedNames,
                    unknownReason: "Remote default branch ref is unavailable."
                ),
                worktreePath: nil,
                isMergedIntoDefaultHint: mergedNames?.contains(reference.name)
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

        let identity = repositoryIdentity ?? GitRepositoryContext.normalizedPath(input.currentWorktreePath)
        return GitWorktreeSnapshot(
            repositoryPath: input.currentWorktreePath,
            defaultBranchName: input.defaultBranchName,
            defaultBranchRef: input.defaultBranchRef,
            analysisDescription: input.analysisDescription,
            worktrees: worktrees,
            branches: branches,
            repositoryIdentity: identity,
            protectedWorktreePaths: input.protectedWorktreePaths,
            cleanupUnits: Self.cleanupUnits(repositoryIdentity: identity, branches: branches, worktrees: worktrees),
            managementUnits: Self.managementUnits(repositoryIdentity: identity, branches: branches, worktrees: worktrees)
        )
    }

    private func branchStatus(
        for reference: GitBranchReference,
        defaultBranchName: String,
        currentBranchName: String?,
        worktreePath: String?,
        mergedNames: Set<String>?,
        unknownReason: String = "Merge status is unavailable."
    ) -> GitBranchCleanupStatus {
        if Self.protectedBranchNames.contains(reference.name) || reference.name == defaultBranchName {
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

    // swiftlint:disable:next cyclomatic_complexity
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
        if protectedWorktreePaths.contains(standardizedPath(worktree.path)) {
            return .unknown(reason: "Worktree is monitored as a project and protected from cleanup.")
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
        return .eligible
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

// MARK: - Cleanup units

extension WorktreeCleanupAnalyzer {
    static func cleanupUnits(
        repositoryIdentity: String,
        branches: [GitBranchCleanupInfo],
        worktrees: [GitWorktreeCleanupInfo]
    ) -> [GitCleanupUnit] {
        let worktreeByBranch: [String: GitWorktreeCleanupInfo] = Dictionary(
            worktrees.compactMap { info in
                guard info.status.isEligible, let branchName = info.worktree.branchName else { return nil }
                return (branchName, info)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return branches.compactMap { branch in
            guard !branch.reference.isRemote else { return nil }
            let linkedWorktree: GitWorktreeCleanupInfo?
            switch branch.status {
            case .mergedIntoDefault:
                linkedWorktree = nil
            case let .checkedOutElsewhere(path):
                linkedWorktree = worktrees.first {
                    $0.status.isEligible
                        && $0.worktree.branchName == branch.reference.name
                        && GitRepositoryContext.normalizedPath($0.worktree.path)
                        == GitRepositoryContext.normalizedPath(path)
                }
                guard linkedWorktree != nil else { return nil }
            default:
                return nil
            }
            return GitCleanupUnit(
                repositoryIdentity: repositoryIdentity,
                branch: branch,
                worktree: linkedWorktree ?? worktreeByBranch[branch.reference.name],
                mode: .safe
            )
        }
    }

    static func managementUnits(
        repositoryIdentity: String,
        branches: [GitBranchCleanupInfo],
        worktrees: [GitWorktreeCleanupInfo]
    ) -> [GitCleanupUnit] {
        let localBranches = branches.filter { !$0.reference.isRemote }
        let worktreeByBranch = Dictionary(
            worktrees.compactMap { info -> (String, GitWorktreeCleanupInfo)? in
                guard let branchName = info.worktree.branchName else { return nil }
                return (branchName, info)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var units = localBranches.map { branch in
            GitCleanupUnit(
                repositoryIdentity: repositoryIdentity,
                branch: branch,
                worktree: worktreeByBranch[branch.reference.name]
            )
        }

        let localBranchNames = Set(localBranches.map(\.reference.name))
        for worktree in worktrees where worktree.worktree.branchName.map({ !localBranchNames.contains($0) }) ?? true {
            let name = worktree.worktree.branchName ?? "detached"
            let branch = GitBranchCleanupInfo(
                reference: GitBranchReference(name: name, headHash: worktree.worktree.headHash, isRemote: false),
                status: .notMerged,
                worktreePath: worktree.worktree.path
            )
            units.append(
                GitCleanupUnit(
                    repositoryIdentity: repositoryIdentity,
                    branch: branch,
                    worktree: worktree,
                    mode: .removeWorktree
                )
            )
        }
        return units
    }
}
