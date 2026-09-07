import Foundation

struct GitCleanupAnalysis: Hashable {
    let repositoryPath: String
    let repositoryIdentity: String
    let defaultBranchRef: String
    let snapshot: GitWorktreeSnapshot
}

struct GitCleanupRepository {
    let runner: GitCommandRunner

    func analyze(
        repositoryPath: String,
        defaultBranchName: String,
        protectedWorktreePaths: Set<String> = []
    ) -> Result<GitCleanupAnalysis, Error> {
        guard let identity = repositoryIdentity(repositoryPath) else {
            return .failure(error("Shared repository identity is unavailable."))
        }
        let defaultBranchRef = "refs/heads/\(defaultBranchName)"
        guard !execute(repositoryPath, ["show-ref", "--verify", "--quiet", defaultBranchRef]).failure else {
            return .failure(error("Default branch '\(defaultBranchName)' is unavailable."))
        }
        guard let worktrees = queryWorktrees(repositoryPath),
              let localBranches = queryReferences(repositoryPath, remote: false),
              let remoteBranches = queryReferences(repositoryPath, remote: true),
              let reachableLocal = queryMerged(repositoryPath, ref: defaultBranchRef, scope: "refs/heads")
        else {
            return .failure(error("Failed to analyze Git worktrees and branches."))
        }
        let mergedLocal = reachableLocal.union(
            cherryPickedBranches(
                repositoryPath,
                upstreamRef: defaultBranchRef,
                references: localBranches
            )
        )
        let currentBranch = queryCurrentBranch(repositoryPath)
        let mergedRemote = queryMergedRemote(
            repositoryPath,
            defaultBranchName: defaultBranchName,
            references: remoteBranches
        )
        let input = GitWorktreeAnalysisInput(
            defaultBranchName: defaultBranchName,
            defaultBranchRef: defaultBranchRef,
            currentBranchName: currentBranch,
            currentWorktreePath: repositoryPath,
            worktrees: updateWorkingTreeStates(worktrees),
            localBranches: localBranches,
            remoteBranches: remoteBranches,
            mergedLocalBranchNames: mergedLocal,
            mergedRemoteBranchNames: nil,
            analysisDescription: "Local Git refs; cherry-picked commits count as merged; remote status uses existing remote-tracking refs.",
            protectedWorktreePaths: protectedWorktreePaths,
            mergedRemoteBranchNamesByRemote: mergedRemote
        )
        let snapshot = WorktreeCleanupAnalyzer().analyze(input)
        return .success(GitCleanupAnalysis(
            repositoryPath: GitRepositoryContext.normalizedPath(repositoryPath),
            repositoryIdentity: identity,
            defaultBranchRef: defaultBranchRef,
            snapshot: GitWorktreeSnapshot(
                repositoryPath: snapshot.repositoryPath,
                defaultBranchName: snapshot.defaultBranchName,
                defaultBranchRef: snapshot.defaultBranchRef,
                analysisDescription: snapshot.analysisDescription,
                worktrees: snapshot.worktrees,
                branches: snapshot.branches,
                repositoryIdentity: identity,
                protectedWorktreePaths: snapshot.protectedWorktreePaths,
                cleanupUnits: GitCleanupUnit.build(
                    repositoryIdentity: identity,
                    branches: snapshot.branches,
                    worktrees: snapshot.worktrees
                ),
                managementUnits: GitCleanupUnit.buildManagementUnits(
                    repositoryIdentity: identity,
                    branches: snapshot.branches,
                    worktrees: snapshot.worktrees
                )
            )
        ))
    }

    func cleanup(
        units: [GitCleanupUnit],
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String,
        projectName: String? = nil,
        progress: (@Sendable (GitCleanupProgress) -> Void)? = nil
    ) -> GitCleanupBatchResult {
        progress?(.init(completed: 0, total: units.count, projectName: projectName, detail: "Checking repository state"))
        guard repositoryIdentity(repositoryPath) == snapshot.repositoryIdentity else {
            progress?(.init(completed: units.count, total: units.count, projectName: projectName, detail: "Cleanup skipped because the repository changed"))
            return GitCleanupBatchResult(items: units.map {
                GitCleanupItemResult(unit: $0, status: .skipped(reason: "The shared repository identity changed; cleanup was skipped."))
            })
        }
        return GitCleanupBatchResult(items: units.enumerated().map { index, unit in
            progress?(.init(
                completed: index,
                total: units.count,
                projectName: projectName,
                detail: cleanupDetail(for: unit)
            ))
            let status = unitValidationReason(unit, snapshot: snapshot)
                .map(GitCleanupItemResultStatus.skipped)
                ?? cleanup(unit, snapshot: snapshot, repositoryPath: repositoryPath)
            let item = GitCleanupItemResult(unit: unit, status: status)
            progress?(.init(
                completed: index + 1,
                total: units.count,
                projectName: projectName,
                detail: "Finished \(unit.title)"
            ))
            return item
        })
    }

    func cleanup(
        targets: [GitCleanupTarget],
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String,
        projectName: String? = nil,
        progress: (@Sendable (GitCleanupProgress) -> Void)? = nil
    ) -> GitCleanupBatchResult {
        progress?(.init(completed: 0, total: targets.count, projectName: projectName, detail: "Checking repository state"))
        guard repositoryIdentity(repositoryPath) == snapshot.repositoryIdentity else {
            progress?(.init(completed: targets.count, total: targets.count, projectName: projectName, detail: "Cleanup skipped because the repository changed"))
            return GitCleanupBatchResult(items: targets.map {
                GitCleanupItemResult(target: $0, status: .skipped(reason: "The shared repository identity changed; cleanup was skipped."))
            })
        }
        return GitCleanupBatchResult(items: targets.enumerated().map { index, target in
            progress?(.init(
                completed: index,
                total: targets.count,
                projectName: projectName,
                detail: "Cleaning \(target.title)"
            ))
            let status: GitCleanupItemResultStatus = if let reason = targetValidationReason(target, snapshot: snapshot) {
                .skipped(reason: reason)
            } else {
                switch target {
                case let .localBranch(info):
                    cleanupBranch(info, snapshot: snapshot, repositoryPath: repositoryPath, requireDetached: true, allowUnmerged: false)
                case let .worktree(info):
                    cleanupWorktree(info, snapshot: snapshot, repositoryPath: repositoryPath, allowUnmerged: false)
                case let .remoteBranch(info):
                    cleanupRemote(info, snapshot: snapshot, repositoryPath: repositoryPath)
                }
            }
            progress?(.init(
                completed: index + 1,
                total: targets.count,
                projectName: projectName,
                detail: "Finished \(target.title)"
            ))
            return GitCleanupItemResult(target: target, status: status)
        })
    }

    private func cleanup(
        _ unit: GitCleanupUnit,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> GitCleanupItemResultStatus {
        let allowUnmerged = unit.isDangerousBranchDeletion
        if unit.isForceWorktreeRemoval {
            guard let worktree = unit.worktree else {
                return .skipped(reason: "The worktree is no longer available for removal.")
            }
            return forceRemoveWorktree(worktree, snapshot: snapshot, repositoryPath: repositoryPath)
        }
        if unit.isWorktreeOnlyAction {
            guard let worktree = unit.worktree else {
                return .skipped(reason: "The worktree is no longer available for removal.")
            }
            return cleanupWorktree(
                worktree,
                snapshot: snapshot,
                repositoryPath: repositoryPath,
                allowUnmerged: true
            )
        }
        if unit.isBranchOnlyAction {
            return cleanupBranch(
                unit.branch,
                snapshot: snapshot,
                repositoryPath: repositoryPath,
                requireDetached: true,
                allowUnmerged: allowUnmerged
            )
        }
        if let worktree = unit.worktree {
            let worktreeStatus = cleanupWorktreeValidation(
                worktree,
                branchName: unit.branch.reference.name,
                snapshot: snapshot,
                repositoryPath: repositoryPath,
                allowUnmerged: allowUnmerged
            )
            if let worktreeStatus {
                return .skipped(reason: worktreeStatus)
            }
            let removed = execute(repositoryPath, ["worktree", "remove", worktree.worktree.path])
            guard !removed.failure else {
                return .failed(reason: "Failed to remove '\(worktree.worktree.path)': \(removed.output)")
            }
            // `git branch --delete` is the final detached-worktree guard after a successful removal.
            let branchStatus = cleanupBranchValidation(
                unit.branch,
                snapshot: snapshot,
                repositoryPath: repositoryPath,
                requireDetached: true,
                allowUnmerged: allowUnmerged
            )
            if let branchStatus {
                return .partiallySucceeded(reason: "Worktree removed, but the branch was kept: \(branchStatus)")
            }
            let deleted = execute(
                repositoryPath,
                branchDeleteArguments(
                    for: unit.branch,
                    defaultBranchRef: snapshot.defaultBranchRef,
                    repositoryPath: repositoryPath,
                    allowUnmerged: allowUnmerged
                )
            )
            return deleted.failure
                ? .partiallySucceeded(reason: "Worktree removed, but branch deletion failed: \(deleted.output)")
                : .succeeded
        }
        return cleanupBranch(
            unit.branch,
            snapshot: snapshot,
            repositoryPath: repositoryPath,
            requireDetached: true,
            allowUnmerged: allowUnmerged
        )
    }

    private func forceRemoveWorktree(
        _ info: GitWorktreeCleanupInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> GitCleanupItemResultStatus {
        if let reason = forceWorktreeValidation(info, snapshot: snapshot, repositoryPath: repositoryPath) {
            return .skipped(reason: reason)
        }
        let result = execute(repositoryPath, ["worktree", "remove", "--force", info.worktree.path])
        return result.failure
            ? .failed(reason: "Failed to force-remove '\(info.worktree.path)': \(result.output)")
            : .succeeded
    }

    private func forceWorktreeValidation(
        _ info: GitWorktreeCleanupInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> String? {
        guard info.status == .dirty, info.worktree.branchName != nil else {
            return "The worktree is no longer eligible for force removal; reload and try again."
        }
        guard !info.worktree.isMainWorktree,
              GitRepositoryContext.normalizedPath(info.worktree.path) != GitRepositoryContext.normalizedPath(repositoryPath)
        else { return "The current worktree cannot be removed." }
        let normalizedPath = GitRepositoryContext.normalizedPath(info.worktree.path)
        guard !snapshot.protectedWorktreePaths.contains(normalizedPath) else {
            return "Worktree is monitored as a project and protected from cleanup."
        }
        guard FileManager.default.fileExists(atPath: info.worktree.path) else {
            return "The worktree path no longer exists."
        }
        guard let current = queryWorktrees(repositoryPath)?.first(where: {
            GitRepositoryContext.normalizedPath($0.path) == normalizedPath
        }) else {
            return "The worktree changed or is no longer registered."
        }
        guard !current.isMainWorktree,
              current.branchName == info.worktree.branchName,
              current.headHash == info.worktree.headHash,
              current.lockReason == nil,
              current.pruneReason == nil
        else {
            return "The worktree changed or is no longer eligible for force removal."
        }
        guard let state = workingTreeState(info.worktree.path) else {
            return "The worktree status is unavailable; reload and try again."
        }
        guard state == .dirty else {
            return "The worktree is no longer dirty; reload and try again."
        }
        return nil
    }

    private func cleanupBranch(
        _ info: GitBranchCleanupInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String,
        requireDetached: Bool,
        allowUnmerged: Bool
    ) -> GitCleanupItemResultStatus {
        guard let reason = cleanupBranchValidation(
            info,
            snapshot: snapshot,
            repositoryPath: repositoryPath,
            requireDetached: requireDetached,
            allowUnmerged: allowUnmerged
        ) else {
            let result = execute(
                repositoryPath,
                branchDeleteArguments(
                    for: info,
                    defaultBranchRef: snapshot.defaultBranchRef,
                    repositoryPath: repositoryPath,
                    allowUnmerged: allowUnmerged
                )
            )
            return result.failure ? .failed(reason: "Failed to delete '\(info.reference.name)': \(result.output)") : .succeeded
        }
        return .skipped(reason: reason)
    }

    private func cleanupBranchValidation(
        _ info: GitBranchCleanupInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String,
        requireDetached: Bool = true,
        allowUnmerged: Bool = false
    ) -> String? {
        guard !info.reference.isRemote else { return "The branch is no longer eligible for local cleanup." }
        switch info.status {
        case .protected, .current, .unknown:
            return "The branch is no longer eligible for local cleanup."
        default:
            break
        }
        guard refHash("refs/heads/\(info.reference.name)", in: repositoryPath) == info.reference.headHash else { return "The branch changed since analysis; it was skipped." }
        guard let currentBranch = queryCurrentBranch(repositoryPath) else { return "The current branch could not be verified; cleanup was skipped." }
        guard currentBranch != info.reference.name else { return "The current branch cannot be deleted." }
        let merged = isMerged(info.reference.name, ref: snapshot.defaultBranchRef, in: repositoryPath)
        guard merged || allowUnmerged else { return "The branch is no longer merged into the default branch." }
        if requireDetached {
            guard let worktrees = queryWorktrees(repositoryPath) else {
                return "Worktree state could not be verified; cleanup was skipped."
            }
            if worktrees.contains(where: { $0.branchName == info.reference.name }) {
                return "The branch is checked out in a worktree."
            }
        }
        return nil
    }

    private func cleanupWorktree(
        _ info: GitWorktreeCleanupInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String,
        allowUnmerged: Bool
    ) -> GitCleanupItemResultStatus {
        if let reason = cleanupWorktreeValidation(
            info,
            branchName: info.worktree.branchName,
            snapshot: snapshot,
            repositoryPath: repositoryPath,
            allowUnmerged: allowUnmerged
        ) {
            return .skipped(reason: reason)
        }
        let result = execute(repositoryPath, ["worktree", "remove", info.worktree.path])
        return result.failure ? .failed(reason: "Failed to remove '\(info.worktree.path)': \(result.output)") : .succeeded
    }

    private func cleanupWorktreeValidation(
        _ info: GitWorktreeCleanupInfo,
        branchName: String?,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String,
        allowUnmerged: Bool = false
    ) -> String? {
        let cleanStatuses: Set<GitWorktreeCleanupStatus> = [.eligible, .branchNotMerged, .detached]
        guard cleanStatuses.contains(info.status) else { return "The worktree is no longer eligible for cleanup." }
        guard !info.worktree.isMainWorktree, GitRepositoryContext.normalizedPath(info.worktree.path) != GitRepositoryContext.normalizedPath(repositoryPath) else { return "The current worktree cannot be removed." }
        guard !snapshot.protectedWorktreePaths.contains(GitRepositoryContext.normalizedPath(info.worktree.path)) else { return "Worktree is monitored as a project and protected from cleanup." }
        guard FileManager.default.fileExists(atPath: info.worktree.path) else { return "The worktree path no longer exists." }
        guard let current = queryWorktrees(repositoryPath)?.first(where: { GitRepositoryContext.normalizedPath($0.path) == GitRepositoryContext.normalizedPath(info.worktree.path) }) else { return "The worktree changed or is no longer registered." }
        guard !current.isMainWorktree,
              current.branchName == branchName,
              current.headHash == info.worktree.headHash,
              current.lockReason == nil,
              current.pruneReason == nil else { return "The worktree changed or is no longer eligible for cleanup." }
        guard isClean(info.worktree.path) else { return "The worktree is no longer eligible for cleanup." }
        if let branch = current.branchName,
           let reason = linkedBranchValidation(
               branch,
               expectedHash: info.worktree.headHash,
               defaultBranchRef: snapshot.defaultBranchRef,
               repositoryPath: repositoryPath,
               allowUnmerged: allowUnmerged
           )
        {
            return reason
        }
        return nil
    }

    private func linkedBranchValidation(
        _ branch: String,
        expectedHash: String,
        defaultBranchRef: String,
        repositoryPath: String,
        allowUnmerged: Bool
    ) -> String? {
        guard let currentHash = refHash("refs/heads/\(branch)", in: repositoryPath) else {
            return allowUnmerged ? nil : "The worktree is no longer eligible for cleanup."
        }
        guard currentHash == expectedHash else { return "The worktree changed or is no longer eligible for cleanup." }
        guard allowUnmerged || isMerged(branch, ref: defaultBranchRef, in: repositoryPath) else {
            return "The linked branch is no longer merged into the default branch."
        }
        return nil
    }

    private func cleanupRemote(_ info: GitBranchCleanupInfo, snapshot _: GitWorktreeSnapshot, repositoryPath: String) -> GitCleanupItemResultStatus {
        guard info.reference.isRemote, info.status == .mergedIntoDefault else { return .skipped(reason: "Remote deletion requires an explicit merged-branch selection.") }
        let remoteName = info.reference.remoteName ?? "origin"
        let ref = "refs/remotes/\(remoteName)/\(info.reference.name)"
        guard refHash(ref, in: repositoryPath) == info.reference.headHash else { return .skipped(reason: "The remote-tracking branch changed since analysis; it was skipped.") }
        let result = execute(repositoryPath, ["push", remoteName, "--delete", info.reference.name], useAuth: true)
        return result.failure ? .failed(reason: "Failed to delete remote branch '\(remoteName)/\(info.reference.name)': \(result.output)") : .succeeded
    }

    private func repositoryIdentity(_ path: String) -> String? {
        let result = execute(path, ["rev-parse", "--git-common-dir"])
        guard !result.failure else { return nil }
        let raw = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let url = URL(fileURLWithPath: raw, relativeTo: URL(fileURLWithPath: path)).standardizedFileURL.resolvingSymlinksInPath()
        return url.path
    }

    private func queryWorktrees(_ path: String) -> [GitWorktreeInfo]? {
        let result = execute(path, ["worktree", "list", "--porcelain"])
        guard !result.failure else { return nil }
        return try? WorktreeParser().parse(result.output)
    }

    private func queryCurrentBranch(_ path: String) -> String? {
        let result = execute(path, ["rev-parse", "--abbrev-ref", "HEAD"])
        guard !result.failure else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "HEAD" ? nil : value
    }

    private func updateWorkingTreeStates(_ worktrees: [GitWorktreeInfo]) -> [GitWorktreeInfo] {
        worktrees.map { info in
            let result = execute(info.path, ["status", "--porcelain", "--untracked-files=all"])
            return GitWorktreeInfo(path: info.path, headHash: info.headHash, branchName: info.branchName, isMainWorktree: info.isMainWorktree, lockReason: info.lockReason, pruneReason: info.pruneReason, workingTreeState: result.failure ? .unknown : (result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .clean : .dirty))
        }
    }

    private func isClean(_ path: String) -> Bool {
        let result = execute(path, ["status", "--porcelain", "--untracked-files=all"])
        return !result.failure && result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func workingTreeState(_ path: String) -> GitWorktreeWorkingTreeState? {
        let result = execute(path, ["status", "--porcelain", "--untracked-files=all"])
        guard !result.failure else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .clean : .dirty
    }

    private func isMerged(_ name: String, ref: String, in path: String) -> Bool {
        queryMerged(path, ref: ref, scope: "refs/heads")?.contains(name) == true
            || isCherryEquivalent(path, upstreamRef: ref, branchRef: name)
    }

    private func refHash(_ ref: String, in path: String) -> String? {
        let result = execute(path, ["rev-parse", "--verify", ref])
        guard !result.failure else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func execute(_ path: String, _ args: [String], useAuth: Bool = false) -> (output: String, failure: Bool) {
        runner.runGitCommand(in: path, args: args, useAuth: useAuth)
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "GitManager", code: 60, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
