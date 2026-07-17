//
//  GitBranchService+Worktrees.swift
//  GitMenuBar
//

import Foundation

extension GitBranchService {
    func resolveWorktreeSnapshotAsync() async -> Result<GitWorktreeSnapshot, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let defaultBranchName = await getDefaultBranchNameAsync()
        let snapshotResult = await runOnBackground {
            self.makeWorktreeSnapshotInput(
                repositoryPath: repositoryPath,
                defaultBranchName: defaultBranchName
            )
        }

        switch snapshotResult {
        case let .failure(error):
            return .failure(error)
        case let .success(input):
            let snapshot = WorktreeCleanupAnalyzer().analyze(input)
            await publishOnMainActor {
                self.worktreeSnapshot = snapshot
            }
            return .success(snapshot)
        }
    }

    private func makeWorktreeSnapshotInput(
        repositoryPath: String,
        defaultBranchName: String
    ) -> Result<GitWorktreeAnalysisInput, Error> {
        let defaultBranchRef = "refs/heads/\(defaultBranchName)"
        let defaultRefResult = executeGitCommand(
            in: repositoryPath,
            args: ["show-ref", "--verify", "--quiet", defaultBranchRef]
        )
        guard !defaultRefResult.failure else {
            return .failure(worktreeQueryError("Default branch '\(defaultBranchName)' is unavailable."))
        }

        guard case let .success(worktrees) = queryWorktrees(in: repositoryPath) else {
            return .failure(worktreeQueryError("Failed to list Git worktrees."))
        }

        guard case let .success(localBranches) = queryBranchReferences(
            in: repositoryPath,
            isRemote: false
        ) else {
            return .failure(worktreeQueryError("Failed to list local branches."))
        }

        guard case let .success(remoteBranches) = queryBranchReferences(
            in: repositoryPath,
            isRemote: true
        ) else {
            return .failure(worktreeQueryError("Failed to list remote branches."))
        }

        guard case let .success(mergedLocalBranchNames) = queryMergedBranchNames(
            in: repositoryPath,
            defaultRef: defaultBranchRef,
            scope: "refs/heads"
        ) else {
            return .failure(worktreeQueryError("Failed to analyze merged branches."))
        }

        let currentBranchName = queryCurrentBranchName(in: repositoryPath)
        let mergedRemoteBranchNames = queryMergedRemoteBranchNames(
            in: repositoryPath,
            defaultBranchName: defaultBranchName
        )
        let input = GitWorktreeAnalysisInput(
            defaultBranchName: defaultBranchName,
            defaultBranchRef: defaultBranchRef,
            currentBranchName: currentBranchName,
            currentWorktreePath: repositoryPath,
            worktrees: updateWorkingTreeStates(worktrees),
            localBranches: localBranches,
            remoteBranches: remoteBranches,
            mergedLocalBranchNames: mergedLocalBranchNames,
            mergedRemoteBranchNames: mergedRemoteBranchNames,
            analysisDescription: "Local Git refs; remote status is based on the last fetch."
        )
        return .success(input)
    }

    private func queryWorktrees(in repositoryPath: String) -> Result<[GitWorktreeInfo], Error> {
        let result = executeGitCommand(in: repositoryPath, args: ["worktree", "list", "--porcelain"])
        guard !result.failure else {
            return .failure(worktreeQueryError("Failed to list Git worktrees: \(result.output)"))
        }
        let worktrees: [GitWorktreeInfo]
        do {
            worktrees = try WorktreeParser().parse(result.output)
        } catch {
            return .failure(error)
        }
        return .success(worktrees)
    }

    private func queryCurrentBranchName(in repositoryPath: String) -> String? {
        let result = executeGitCommand(
            in: repositoryPath,
            args: ["rev-parse", "--abbrev-ref", "HEAD"]
        )
        guard !result.failure else {
            return nil
        }
        let name = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name == "HEAD" ? nil : name
    }

    private func queryBranchReferences(
        in repositoryPath: String,
        isRemote: Bool
    ) -> Result<[GitBranchReference], Error> {
        let scope = isRemote ? "refs/remotes/origin" : "refs/heads"
        let result = executeGitCommand(
            in: repositoryPath,
            args: [
                "for-each-ref",
                "--format=%(refname:short)%00%(objectname)",
                scope
            ]
        )
        guard !result.failure else {
            let kind = isRemote ? "remote" : "local"
            return .failure(worktreeQueryError("Failed to list \(kind) branches: \(result.output)"))
        }
        return .success(parseReferences(result.output, isRemote: isRemote))
    }

    private func queryMergedBranchNames(
        in repositoryPath: String,
        defaultRef: String,
        scope: String
    ) -> Result<Set<String>, Error> {
        let result = executeGitCommand(
            in: repositoryPath,
            args: [
                "for-each-ref",
                "--merged=\(defaultRef)",
                "--format=%(refname:short)",
                scope
            ]
        )
        guard !result.failure else {
            return .failure(worktreeQueryError("Failed to analyze merged branches: \(result.output)"))
        }
        return .success(Set(parseNames(result.output)))
    }

    private func queryMergedRemoteBranchNames(
        in repositoryPath: String,
        defaultBranchName: String
    ) -> Set<String>? {
        let defaultRemoteRef = "refs/remotes/origin/\(defaultBranchName)"
        let remoteRefResult = executeGitCommand(
            in: repositoryPath,
            args: ["show-ref", "--verify", "--quiet", defaultRemoteRef]
        )
        guard !remoteRefResult.failure else {
            return nil
        }
        let result = executeGitCommand(
            in: repositoryPath,
            args: [
                "for-each-ref",
                "--merged=\(defaultRemoteRef)",
                "--format=%(refname:short)",
                "refs/remotes/origin"
            ]
        )
        guard !result.failure else {
            return nil
        }
        return Set(
            parseNames(result.output)
                .filter { $0 != "origin/HEAD" }
                .map { String($0.dropFirst("origin/".count)) }
        )
    }

    private func updateWorkingTreeStates(
        _ worktrees: [GitWorktreeInfo]
    ) -> [GitWorktreeInfo] {
        worktrees.map { worktree in
            let result = executeGitCommand(
                in: worktree.path,
                args: ["status", "--porcelain", "--untracked-files=all"]
            )
            return GitWorktreeInfo(
                path: worktree.path,
                headHash: worktree.headHash,
                branchName: worktree.branchName,
                isMainWorktree: worktree.isMainWorktree,
                lockReason: worktree.lockReason,
                pruneReason: worktree.pruneReason,
                workingTreeState: workingTreeState(for: result)
            )
        }
    }

    private func parseReferences(
        _ output: String,
        isRemote: Bool
    ) -> [GitBranchReference] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line in
                let parts = line.components(separatedBy: "\u{0}")
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                    return nil
                }
                let name = isRemote && parts[0].hasPrefix("origin/")
                    ? String(parts[0].dropFirst("origin/".count))
                    : parts[0]
                return GitBranchReference(name: name, headHash: parts[1], isRemote: isRemote)
            }
            .filter { $0.name != "HEAD" }
    }

    private func workingTreeState(
        for result: (output: String, failure: Bool)
    ) -> GitWorktreeWorkingTreeState {
        guard !result.failure else {
            return .unknown
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .clean
            : .dirty
    }

    private func parseNames(_ output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func worktreeQueryError(_ description: String) -> NSError {
        NSError(
            domain: "GitManager",
            code: 60,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
