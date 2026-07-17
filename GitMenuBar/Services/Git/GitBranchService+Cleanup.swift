import Foundation

extension GitBranchService {
    func performCleanupAsync(
        targets: [GitCleanupTarget],
        snapshot: GitWorktreeSnapshot
    ) async -> Result<GitCleanupBatchResult, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }
        guard standardizedPath(repositoryPath) == standardizedPath(snapshot.repositoryPath) else {
            return .failure(cleanupError("The repository changed before cleanup started. Reload and try again."))
        }

        let result = await runOnBackground {
            self.performCleanup(targets: targets, snapshot: snapshot, repositoryPath: repositoryPath)
        }
        if !targets.isEmpty {
            refreshHandler {}
        }
        return .success(result)
    }

    private func performCleanup(
        targets: [GitCleanupTarget],
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> GitCleanupBatchResult {
        var results: [GitCleanupItemResult] = []
        for target in targets {
            let status = cleanup(target: target, snapshot: snapshot, repositoryPath: repositoryPath)
            results.append(GitCleanupItemResult(target: target, status: status))
        }
        return GitCleanupBatchResult(items: results)
    }

    private func cleanup(
        target: GitCleanupTarget,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> GitCleanupItemResultStatus {
        switch target {
        case let .localBranch(info):
            guard let reason = localBranchValidationFailure(
                info: info,
                snapshot: snapshot,
                repositoryPath: repositoryPath,
                requireDetached: true
            ) else {
                let result = executeGitCommand(
                    in: repositoryPath,
                    args: ["branch", "--delete", info.reference.name]
                )
                return result.failure
                    ? .failed(reason: "Failed to delete '\(info.reference.name)': \(result.output)")
                    : .succeeded
            }
            return .skipped(reason: reason)

        case let .worktree(info):
            guard let reason = worktreeValidationFailure(
                info: info,
                snapshot: snapshot,
                repositoryPath: repositoryPath
            ) else {
                let result = executeGitCommand(
                    in: repositoryPath,
                    args: ["worktree", "remove", info.worktree.path]
                )
                return result.failure
                    ? .failed(reason: "Failed to remove '\(info.worktree.path)': \(result.output)")
                    : .succeeded
            }
            return .skipped(reason: reason)

        case let .remoteBranch(info):
            guard let reason = remoteBranchValidationFailure(
                info: info,
                snapshot: snapshot,
                repositoryPath: repositoryPath
            ) else {
                let result = executeGitCommand(
                    in: repositoryPath,
                    args: ["push", "origin", "--delete", info.reference.name],
                    useAuth: true
                )
                return result.failure
                    ? .failed(reason: "Failed to delete remote branch 'origin/\(info.reference.name)': \(result.output)")
                    : .succeeded
            }
            return .skipped(reason: reason)
        }
    }

    private func localBranchValidationFailure(
        info: GitBranchCleanupInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String,
        requireDetached: Bool
    ) -> String? {
        guard info.isEligible, !info.reference.isRemote else {
            return "The branch is not currently eligible for local cleanup."
        }
        guard !protectedBranchNames.contains(info.reference.name) else {
            return "Protected branches cannot be deleted."
        }
        guard let actualHash = branchHash(name: info.reference.name, repositoryPath: repositoryPath) else {
            return "The branch no longer exists."
        }
        guard actualHash == info.reference.headHash else {
            return "The branch changed since analysis; it was skipped."
        }
        guard currentBranchName(repositoryPath: repositoryPath) != info.reference.name else {
            return "The current branch cannot be deleted."
        }
        guard isMerged(
            branchName: info.reference.name,
            defaultBranchRef: snapshot.defaultBranchRef,
            repositoryPath: repositoryPath
        ) else {
            return "The branch is no longer merged into the default branch."
        }
        if requireDetached {
            guard !isBranchCheckedOut(
                info.reference.name,
                repositoryPath: repositoryPath
            ) else {
                return "The branch is checked out in a worktree."
            }
        }
        return nil
    }

    private func worktreeValidationFailure(
        info: GitWorktreeCleanupInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> String? {
        guard info.status.isEligible else {
            return "The worktree is no longer eligible for cleanup."
        }
        guard !info.worktree.isMainWorktree else {
            return "The main worktree cannot be removed."
        }
        guard standardizedPath(info.worktree.path) != standardizedPath(repositoryPath) else {
            return "The current worktree cannot be removed."
        }
        guard FileManager.default.fileExists(atPath: info.worktree.path) else {
            return "The worktree path no longer exists."
        }
        guard let currentInfo = worktreeInfo(
            at: info.worktree.path,
            repositoryPath: repositoryPath
        ) else {
            return "The worktree changed or is no longer registered."
        }
        if let stateFailure = worktreeStateValidationFailure(
            currentInfo: currentInfo,
            analyzedInfo: info
        ) {
            return stateFailure
        }
        return worktreeBranchValidationFailure(
            currentInfo: currentInfo,
            snapshot: snapshot,
            repositoryPath: repositoryPath
        )
    }

    private func worktreeStateValidationFailure(
        currentInfo: GitWorktreeInfo,
        analyzedInfo: GitWorktreeCleanupInfo
    ) -> String? {
        guard !currentInfo.isMainWorktree else {
            return "The main worktree cannot be removed."
        }
        guard currentInfo.headHash == analyzedInfo.worktree.headHash else {
            return "The worktree HEAD changed since analysis; it was skipped."
        }
        guard currentInfo.lockReason == nil, currentInfo.pruneReason == nil else {
            return "The worktree is locked or prunable."
        }
        guard isClean(path: analyzedInfo.worktree.path) else {
            return "The worktree has uncommitted changes."
        }
        return nil
    }

    private func worktreeBranchValidationFailure(
        currentInfo: GitWorktreeInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> String? {
        guard let branchName = currentInfo.branchName else {
            return "Detached worktrees cannot be removed by safe cleanup."
        }
        guard branchHash(name: branchName, repositoryPath: repositoryPath) != nil else {
            return "The linked branch no longer exists."
        }
        guard isMerged(
            branchName: branchName,
            defaultBranchRef: snapshot.defaultBranchRef,
            repositoryPath: repositoryPath
        ) else {
            return "The linked branch is no longer merged into the default branch."
        }
        return nil
    }

    private func remoteBranchValidationFailure(
        info: GitBranchCleanupInfo,
        snapshot: GitWorktreeSnapshot,
        repositoryPath: String
    ) -> String? {
        guard info.reference.isRemote, case .mergedIntoDefault = info.status else {
            return "Remote deletion requires an explicit merged-branch selection."
        }
        let ref = "refs/remotes/origin/\(info.reference.name)"
        guard let actualHash = refHash(ref: ref, repositoryPath: repositoryPath) else {
            return "The remote-tracking branch no longer exists."
        }
        guard actualHash == info.reference.headHash else {
            return "The remote-tracking branch changed since analysis; it was skipped."
        }
        let defaultRemoteRef = "refs/remotes/origin/\(snapshot.defaultBranchName)"
        guard isMerged(
            branchName: info.reference.name,
            defaultBranchRef: defaultRemoteRef,
            repositoryPath: repositoryPath,
            scope: "refs/remotes/origin",
            remote: true
        ) else {
            return "The remote branch is no longer merged into the remote default branch."
        }
        return nil
    }

    private func worktreeInfo(at path: String, repositoryPath: String) -> GitWorktreeInfo? {
        let result = executeGitCommand(in: repositoryPath, args: ["worktree", "list", "--porcelain"])
        guard !result.failure else { return nil }
        return try? WorktreeParser().parse(result.output).first {
            standardizedPath($0.path) == standardizedPath(path)
        }
    }

    private func isBranchCheckedOut(_ name: String, repositoryPath: String) -> Bool {
        let result = executeGitCommand(in: repositoryPath, args: ["worktree", "list", "--porcelain"])
        guard !result.failure, let worktrees = try? WorktreeParser().parse(result.output) else {
            return true
        }
        return worktrees.contains { $0.branchName == name }
    }

    private func isClean(path: String) -> Bool {
        let result = executeGitCommand(
            in: path,
            args: ["status", "--porcelain", "--untracked-files=all"]
        )
        return !result.failure && result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func branchHash(name: String, repositoryPath: String) -> String? {
        refHash(ref: "refs/heads/\(name)", repositoryPath: repositoryPath)
    }

    private func refHash(ref: String, repositoryPath: String) -> String? {
        let result = executeGitCommand(
            in: repositoryPath,
            args: ["rev-parse", "--verify", ref]
        )
        guard !result.failure else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentBranchName(repositoryPath: String) -> String? {
        let result = executeGitCommand(
            in: repositoryPath,
            args: ["rev-parse", "--abbrev-ref", "HEAD"]
        )
        guard !result.failure else { return nil }
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name == "HEAD" ? nil : name
    }

    private func isMerged(
        branchName: String,
        defaultBranchRef: String,
        repositoryPath: String,
        scope: String = "refs/heads",
        remote: Bool = false
    ) -> Bool {
        let result = executeGitCommand(
            in: repositoryPath,
            args: [
                "for-each-ref",
                "--merged=\(defaultBranchRef)",
                "--format=%(refname:short)",
                scope
            ]
        )
        guard !result.failure else { return false }
        let expectedName = remote ? "origin/\(branchName)" : branchName
        return result.output.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == expectedName
        }
    }

    private var protectedBranchNames: Set<String> {
        ["main", "master", "develop"]
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func cleanupError(_ description: String) -> NSError {
        NSError(
            domain: "GitManager",
            code: 70,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
