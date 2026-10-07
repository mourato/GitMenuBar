//
//  GitBranchService+Mutations.swift
//  GitMenuBar
//

import Foundation

extension GitBranchService {
    func pushNamedLocalBranchAsync(branchName: String, repositoryPath: String) async -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure(GitOperationError.invalidInput("Branch name cannot be empty"))
        }

        return await runOnBackground {
            let verify = self.executeGitCommand(
                in: repositoryPath,
                args: ["show-ref", "--verify", "--quiet", "refs/heads/\(trimmedName)"]
            )
            guard !verify.failure else {
                return .failure(GitOperationError.invalidState("Local branch '\(trimmedName)' is no longer in this repository."))
            }

            let result = self.executeGitCommand(
                in: repositoryPath,
                args: ["push", "origin", "refs/heads/\(trimmedName):refs/heads/\(trimmedName)"],
                useAuth: true
            )
            guard !result.failure else {
                return .failure(GitOperationError.commandFailed(GitStashService.userFacingMessage(from: result.output)))
            }
            return .success(())
        }
    }

    func pushBranchToRemoteAsync(branchName: String) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["push", "-u", "origin", branchName], useAuth: true)
        }

        guard !result.failure else {
            return .failure(GitOperationError.commandFailed("Failed to push '\(branchName)': \(result.output)"))
        }
        return .success(())
    }

    func deleteRemoteBranchAsync(branchName: String, remoteName: String = "origin") async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["push", remoteName, "--delete", branchName], useAuth: true)
        }

        guard !result.failure else {
            return .failure(GitOperationError.commandFailed("Failed to delete remote branch '\(remoteName)/\(branchName)': \(result.output)"))
        }
        return .success(())
    }

    func createBranchFromCurrentHead(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        createBranch(branchName: branchName, fromBranch: nil, completion: completion)
    }

    func switchBranchAsync(
        branchName: String,
        repositoryPath: String? = nil
    ) async -> Result<Void, Error> {
        let targetPath = repositoryPath ?? storedRepoPath
        guard !targetPath.isEmpty else {
            return .failure(GitOperationError.noRepository)
        }

        // Check if we have uncommitted changes
        let statusResult = await runOnBackground {
            self.executeGitCommand(in: targetPath, args: ["status", "--porcelain"])
        }
        let hasChanges = !statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        var stashCreated = false

        // If we have changes, stash them first
        if hasChanges {
            let stashResult = await runOnBackground {
                self.executeGitCommand(
                    in: targetPath,
                    args: ["stash", "push", "-u", "-m", "GitMenuBar auto-stash for branch switch"]
                )
            }

            if stashResult.failure {
                return .failure(GitOperationError.commandFailed("Failed to save changes: \(stashResult.output)"))
            }
            stashCreated = true
            print("Stashed changes before switching branches")
        }

        // Try to switch/checkout branch
        let checkoutResult = await runOnBackground {
            self.executeGitCommand(in: targetPath, args: ["checkout", branchName])
        }

        if checkoutResult.failure {
            // If checkout failed and we stashed, try to restore the stash
            if stashCreated {
                _ = await runOnBackground {
                    self.executeGitCommand(in: targetPath, args: ["stash", "pop"])
                }
            }
            return .failure(GitOperationError.commandFailed("Failed to switch branch: \(checkoutResult.output)"))
        }

        print("Successfully switched to branch: \(branchName)")

        // If we stashed changes, restore them
        if stashCreated {
            let popResult = await runOnBackground {
                self.executeGitCommand(in: targetPath, args: ["stash", "pop"])
            }

            if popResult.failure {
                // Stash pop failed - likely due to conflicts
                return .failure(GitOperationError.conflict("Switched branches, but couldn't reapply your changes due to conflicts. Run 'git stash pop' manually to resolve."))
            }
            print("Restored stashed changes after branch switch")
        }

        return .success(())
    }

    func switchBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(GitOperationError.noRepository))
            return
        }

        Task { @MainActor in
            let result = await switchBranchAsync(branchName: branchName)
            switch result {
            case .success:
                self.refreshHandler {
                    completion(.success(()))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func createBranchAsync(
        branchName: String,
        fromBranch: String? = nil,
        repositoryPath: String? = nil
    ) async -> Result<Void, Error> {
        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure(GitOperationError.invalidInput("Branch name cannot be empty"))
        }

        let targetPath = repositoryPath ?? storedRepoPath
        guard !targetPath.isEmpty else {
            return .failure(GitOperationError.noRepository)
        }

        let args = {
            var args = ["checkout", "-b", trimmedName]
            if let fromBranch, !fromBranch.isEmpty {
                args.append(fromBranch)
            }
            return args
        }()

        let result = await runOnBackground {
            self.executeGitCommand(in: targetPath, args: args)
        }

        if result.failure {
            let output = result.output
            var friendlyMessage = "Failed to create branch"

            if output.contains("already exists") {
                friendlyMessage = "Branch '\(trimmedName)' already exists"
            } else if output.contains("not a valid branch name") || output.contains("invalid ref format") {
                friendlyMessage = "Invalid branch name"
            } else if output.contains("not found") || output.contains("does not exist") {
                friendlyMessage = "Source branch not found"
            } else {
                let errorSnippet = output.components(separatedBy: "\n").first ?? output
                friendlyMessage = errorSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return .failure(GitOperationError.commandFailed(friendlyMessage))
        }

        print("Successfully created and switched to branch: \(trimmedName)")
        return .success(())
    }

    func createBranch(branchName: String, fromBranch: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(GitOperationError.noRepository))
            return
        }

        Task { @MainActor in
            let result = await createBranchAsync(branchName: branchName, fromBranch: fromBranch)
            switch result {
            case .success:
                self.refreshHandler {
                    completion(.success(()))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func mergeBranchAsync(
        fromBranch: String,
        repositoryPath: String? = nil
    ) async -> Result<Void, Error> {
        let targetPath = repositoryPath ?? storedRepoPath
        guard !targetPath.isEmpty else {
            return .failure(GitOperationError.noRepository)
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: targetPath, args: ["merge", fromBranch])
        }

        if result.failure {
            if result.output.contains("CONFLICT") || result.output.contains("Automatic merge failed") {
                return .failure(GitOperationError.conflict("Merge conflict! Please resolve manually."))
            } else {
                return .failure(GitOperationError.commandFailed("Failed to merge: \(result.output)"))
            }
        }

        print("Successfully merged \(fromBranch) into current branch")
        return .success(())
    }

    func mergeBranch(fromBranch: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(GitOperationError.noRepository))
            return
        }

        Task { @MainActor in
            let result = await mergeBranchAsync(fromBranch: fromBranch)
            switch result {
            case .success:
                self.refreshHandler {
                    completion(.success(()))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func deleteBranchAsync(
        branchName: String,
        force: Bool = false,
        repositoryPath: String? = nil
    ) async -> Result<Void, Error> {
        let targetPath = repositoryPath ?? storedRepoPath
        guard !targetPath.isEmpty else {
            return .failure(GitOperationError.noRepository)
        }

        if branchName == currentBranch {
            return .failure(GitOperationError.invalidState("Cannot delete the currently checked out branch"))
        }

        let expectedHash = await runOnBackground { () -> String? in
            let result = self.executeGitCommand(
                in: targetPath,
                args: ["rev-parse", "--verify", "refs/heads/\(branchName)"]
            )
            guard !result.failure else { return nil }
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let expectedHash, !expectedHash.isEmpty else {
            return .failure(GitOperationError.invalidState("Branch '\(branchName)' no longer exists."))
        }

        if let reason = await branchDeletionValidation(
            branchName: branchName,
            expectedHash: expectedHash,
            in: targetPath
        ) {
            return .failure(GitOperationError.invalidState(reason))
        }

        let localResult = await runOnBackground {
            self.executeGitCommand(
                in: targetPath,
                args: force ? ["branch", "--delete", "--force", branchName] : ["branch", "--delete", branchName]
            )
        }

        if localResult.failure {
            return .failure(GitOperationError.commandFailed("Failed to delete local branch: \(localResult.output)"))
        }

        print("Successfully deleted local branch: \(branchName)")
        return .success(())
    }

    func deleteBranch(branchName: String, force: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(GitOperationError.noRepository))
            return
        }

        Task { @MainActor in
            let result = await deleteBranchAsync(branchName: branchName, force: force)
            switch result {
            case .success:
                self.fetchBranches {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func branchDeletionValidation(
        branchName: String,
        expectedHash: String,
        in repositoryPath: String
    ) async -> String? {
        await runOnBackground {
            let currentHash = self.executeGitCommand(
                in: repositoryPath,
                args: ["rev-parse", "--verify", "refs/heads/\(branchName)"]
            )
            guard !currentHash.failure else {
                return "Branch '\(branchName)' no longer exists."
            }
            guard currentHash.output.trimmingCharacters(in: .whitespacesAndNewlines) == expectedHash else {
                return "Branch '\(branchName)' changed since confirmation; it was not deleted."
            }

            let current = self.executeGitCommand(
                in: repositoryPath,
                args: ["rev-parse", "--abbrev-ref", "HEAD"]
            )
            guard !current.failure else {
                return "The current branch could not be verified; reload and try again."
            }
            let currentBranch = current.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentBranch != branchName else {
                return "Cannot delete the currently checked out branch."
            }

            _ = self.executeGitCommand(in: repositoryPath, args: ["worktree", "prune"])
            let list = self.executeGitCommand(in: repositoryPath, args: ["worktree", "list", "--porcelain"])
            guard !list.failure, let worktrees = try? WorktreeParser().parse(list.output) else {
                return "Worktree state could not be verified; reload and try again."
            }
            if let holder = worktrees.first(where: { $0.branchName == branchName })?.path {
                return "Branch '\(branchName)' is checked out in worktree at '\(holder)'. Remove the worktree first — Manage Branches → Cleanup removes both."
            }
            return nil
        }
    }

    func renameBranchAsync(
        oldName: String,
        newName: String,
        repositoryPath: String? = nil
    ) async -> Result<Void, Error> {
        guard !oldName.isEmpty else {
            return .failure(GitOperationError.invalidInput("Old branch name cannot be empty"))
        }

        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty else {
            return .failure(GitOperationError.invalidInput("New branch name cannot be empty"))
        }

        let targetPath = repositoryPath ?? storedRepoPath
        guard !targetPath.isEmpty else {
            return .failure(GitOperationError.noRepository)
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: targetPath, args: ["branch", "-m", oldName, trimmedNewName])
        }

        if result.failure {
            return .failure(GitOperationError.commandFailed("Failed to rename branch: \(result.output)"))
        }

        print("Successfully renamed branch from \(oldName) to \(trimmedNewName)")
        return .success(())
    }

    func renameBranch(oldName: String, newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(GitOperationError.noRepository))
            return
        }

        Task { @MainActor in
            let result = await renameBranchAsync(oldName: oldName, newName: newName)
            switch result {
            case .success:
                self.refreshHandler {
                    completion(.success(()))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}
