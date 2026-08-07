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
              let mergedLocal = queryMerged(repositoryPath, ref: defaultBranchRef, scope: "refs/heads")
        else {
            return .failure(error("Failed to analyze Git worktrees and branches."))
        }
        let currentBranch = queryCurrentBranch(repositoryPath)
        let mergedRemote = queryMergedRemote(repositoryPath, defaultBranchName: defaultBranchName)
        let input = GitWorktreeAnalysisInput(
            defaultBranchName: defaultBranchName,
            defaultBranchRef: defaultBranchRef,
            currentBranchName: currentBranch,
            currentWorktreePath: repositoryPath,
            worktrees: updateWorkingTreeStates(worktrees),
            localBranches: localBranches,
            remoteBranches: remoteBranches,
            mergedLocalBranchNames: mergedLocal,
            mergedRemoteBranchNames: mergedRemote,
            analysisDescription: "Local Git refs; remote status uses existing remote-tracking refs.",
            protectedWorktreePaths: protectedWorktreePaths
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
                cleanupUnits: GitCleanupUnit.build(
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
        repositoryPath: String
    ) -> GitCleanupBatchResult {
        GitCleanupBatchResult(items: units.map { unit in
            GitCleanupItemResult(unit: unit, status: cleanup(unit, snapshot: snapshot, repositoryPath: repositoryPath))
        })
    }

    func cleanup(
        targets: [GitCleanupTarget],
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> GitCleanupBatchResult {
        GitCleanupBatchResult(items: targets.map { target in
            let status: GitCleanupItemResultStatus = switch target {
            case let .localBranch(info):
                cleanupBranch(info, snapshot: snapshot, repositoryPath: repositoryPath, requireDetached: true)
            case let .worktree(info):
                cleanupWorktree(info, snapshot: snapshot, repositoryPath: repositoryPath)
            case let .remoteBranch(info):
                cleanupRemote(info, snapshot: snapshot, repositoryPath: repositoryPath)
            }
            return GitCleanupItemResult(target: target, status: status)
        })
    }

    private func cleanup(
        _ unit: GitCleanupUnit,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> GitCleanupItemResultStatus {
        guard unit.branch.status == .mergedIntoDefault || unit.branch.status.isCheckedOutElsewhere else { return .skipped(reason: "The branch is no longer eligible for cleanup.") }
        if let worktree = unit.worktree {
            let worktreeStatus = cleanupWorktreeValidation(worktree, snapshot: snapshot, repositoryPath: repositoryPath)
            if let worktreeStatus {
                return .skipped(reason: worktreeStatus)
            }
            let removed = execute(repositoryPath, ["worktree", "remove", worktree.worktree.path])
            guard !removed.failure else {
                return .failed(reason: "Failed to remove '\(worktree.worktree.path)': \(removed.output)")
            }
            let branchStatus = cleanupBranchValidation(unit.branch, snapshot: snapshot, repositoryPath: repositoryPath)
            if let branchStatus {
                return .partiallySucceeded(reason: "Worktree removed, but the branch was kept: \(branchStatus)")
            }
            let deleted = execute(repositoryPath, ["branch", "--delete", unit.branch.reference.name])
            return deleted.failure
                ? .partiallySucceeded(reason: "Worktree removed, but branch deletion failed: \(deleted.output)")
                : .succeeded
        }
        return cleanupBranch(unit.branch, snapshot: snapshot, repositoryPath: repositoryPath, requireDetached: true)
    }

    private func cleanupBranch(_ info: GitBranchCleanupInfo, snapshot: GitWorktreeSnapshot, repositoryPath: String, requireDetached: Bool) -> GitCleanupItemResultStatus {
        guard let reason = cleanupBranchValidation(info, snapshot: snapshot, repositoryPath: repositoryPath, requireDetached: requireDetached) else {
            let result = execute(repositoryPath, ["branch", "--delete", info.reference.name])
            return result.failure ? .failed(reason: "Failed to delete '\(info.reference.name)': \(result.output)") : .succeeded
        }
        return .skipped(reason: reason)
    }

    private func cleanupBranchValidation(_ info: GitBranchCleanupInfo, snapshot: GitWorktreeSnapshot, repositoryPath: String, requireDetached: Bool = true) -> String? {
        guard !info.reference.isRemote, info.status == .mergedIntoDefault || info.status.isCheckedOutElsewhere else { return "The branch is no longer eligible for local cleanup." }
        guard refHash("refs/heads/\(info.reference.name)", in: repositoryPath) == info.reference.headHash else { return "The branch changed since analysis; it was skipped." }
        guard queryCurrentBranch(repositoryPath) != info.reference.name else { return "The current branch cannot be deleted." }
        guard isMerged(info.reference.name, ref: snapshot.defaultBranchRef, in: repositoryPath) else { return "The branch is no longer merged into the default branch." }
        if requireDetached, queryWorktrees(repositoryPath)?.contains(where: { $0.branchName == info.reference.name }) == true {
            return "The branch is checked out in a worktree."
        }
        return nil
    }

    private func cleanupWorktree(_ info: GitWorktreeCleanupInfo, snapshot: GitWorktreeSnapshot, repositoryPath: String) -> GitCleanupItemResultStatus {
        guard let reason = cleanupWorktreeValidation(info, snapshot: snapshot, repositoryPath: repositoryPath) else {
            let result = execute(repositoryPath, ["worktree", "remove", info.worktree.path])
            return result.failure ? .failed(reason: "Failed to remove '\(info.worktree.path)': \(result.output)") : .succeeded
        }
        return .skipped(reason: reason)
    }

    private func cleanupWorktreeValidation(_ info: GitWorktreeCleanupInfo, snapshot: GitWorktreeSnapshot, repositoryPath: String) -> String? {
        guard info.status.isEligible else { return "The worktree is no longer eligible for cleanup." }
        guard !info.worktree.isMainWorktree, GitRepositoryContext.normalizedPath(info.worktree.path) != GitRepositoryContext.normalizedPath(repositoryPath) else { return "The current worktree cannot be removed." }
        guard FileManager.default.fileExists(atPath: info.worktree.path) else { return "The worktree path no longer exists." }
        guard let current = queryWorktrees(repositoryPath)?.first(where: { GitRepositoryContext.normalizedPath($0.path) == GitRepositoryContext.normalizedPath(info.worktree.path) }) else { return "The worktree changed or is no longer registered." }
        guard current.headHash == info.worktree.headHash, current.lockReason == nil, current.pruneReason == nil, current.branchName != nil else { return "The worktree changed or is no longer eligible for cleanup." }
        guard let branch = current.branchName,
              isClean(info.worktree.path),
              refHash("refs/heads/\(branch)", in: repositoryPath) != nil else { return "The worktree is no longer eligible for cleanup." }
        guard isMerged(branch, ref: snapshot.defaultBranchRef, in: repositoryPath) else { return "The linked branch is no longer merged into the default branch." }
        return nil
    }

    private func cleanupRemote(_ info: GitBranchCleanupInfo, snapshot _: GitWorktreeSnapshot, repositoryPath: String) -> GitCleanupItemResultStatus {
        guard info.reference.isRemote, info.status == .mergedIntoDefault else { return .skipped(reason: "Remote deletion requires an explicit merged-branch selection.") }
        let ref = "refs/remotes/origin/\(info.reference.name)"
        guard refHash(ref, in: repositoryPath) == info.reference.headHash else { return .skipped(reason: "The remote-tracking branch changed since analysis; it was skipped.") }
        let result = execute(repositoryPath, ["push", "origin", "--delete", info.reference.name], useAuth: true)
        return result.failure ? .failed(reason: "Failed to delete remote branch 'origin/\(info.reference.name)': \(result.output)") : .succeeded
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

    private func queryReferences(_ path: String, remote: Bool) -> [GitBranchReference]? {
        let scope = remote ? "refs/remotes/origin" : "refs/heads"
        let result = execute(path, ["for-each-ref", "--format=%(refname:short)%00%(objectname)", scope])
        guard !result.failure else { return nil }
        return result.output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "\u{0}")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            let name = remote && parts[0].hasPrefix("origin/") ? String(parts[0].dropFirst(7)) : parts[0]
            return name == "HEAD" ? nil : GitBranchReference(name: name, headHash: parts[1], isRemote: remote)
        }
    }

    private func queryMerged(_ path: String, ref: String, scope: String) -> Set<String>? {
        let result = execute(path, ["for-each-ref", "--merged=\(ref)", "--format=%(refname:short)", scope])
        guard !result.failure else { return nil }
        return Set(result.output.split(whereSeparator: \.isNewline).map(String.init))
    }

    private func queryMergedRemote(_ path: String, defaultBranchName: String) -> Set<String>? {
        let ref = "refs/remotes/origin/\(defaultBranchName)"
        guard !execute(path, ["show-ref", "--verify", "--quiet", ref]).failure,
              let names = queryMerged(path, ref: ref, scope: "refs/remotes/origin") else { return nil }
        return Set(names.filter { $0 != "origin/HEAD" }.map { $0.hasPrefix("origin/") ? String($0.dropFirst(7)) : $0 })
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

    private func isMerged(_ name: String, ref: String, in path: String) -> Bool {
        queryMerged(path, ref: ref, scope: "refs/heads")?.contains(name) == true
    }

    private func refHash(_ ref: String, in path: String) -> String? {
        let result = execute(path, ["rev-parse", "--verify", ref])
        guard !result.failure else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func execute(_ path: String, _ args: [String], useAuth: Bool = false) -> (output: String, failure: Bool) {
        runner.runGitCommand(in: path, args: args, useAuth: useAuth)
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "GitManager", code: 60, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
