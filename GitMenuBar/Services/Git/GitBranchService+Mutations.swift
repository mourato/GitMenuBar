//
//  GitBranchService+Mutations.swift
//  GitMenuBar
//

import Foundation

extension GitBranchService {
    func pushBranchToRemoteAsync(branchName: String) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["push", "-u", "origin", branchName], useAuth: true)
        }

        guard !result.failure else {
            return .failure(NSError(
                domain: "GitManager",
                code: 40,
                userInfo: [NSLocalizedDescriptionKey: "Failed to push '\(branchName)': \(result.output)"]
            ))
        }
        return .success(())
    }

    func deleteRemoteBranchAsync(branchName: String) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["push", "origin", "--delete", branchName], useAuth: true)
        }

        guard !result.failure else {
            return .failure(NSError(
                domain: "GitManager",
                code: 41,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete remote branch '\(branchName)': \(result.output)"]
            ))
        }
        return .success(())
    }

    func createBranchFromCurrentHead(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Branch name cannot be empty"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Create and checkout new branch from HEAD
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "-b", trimmedName])

            if result.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create branch: \(result.output)"])))
                }
            } else {
                print("Successfully created and switched to branch \(trimmedName)")
                DispatchQueue.main.async {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func switchBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Check if we have uncommitted changes
            let statusResult = self.executeGitCommand(in: self.storedRepoPath, args: ["status", "--porcelain"])
            let hasChanges = !statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            var stashCreated = false

            // If we have changes, stash them first
            if hasChanges {
                let stashResult = self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "push", "-u", "-m", "GitMenuBar auto-stash for branch switch"])

                if stashResult.failure {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to save changes: \(stashResult.output)"])))
                    }
                    return
                }
                stashCreated = true
                print("Stashed changes before switching branches")
            }

            // Try to switch/checkout branch
            let checkoutResult = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", branchName])

            if checkoutResult.failure {
                // If checkout failed and we stashed, try to restore the stash
                if stashCreated {
                    _ = self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "pop"])
                }
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to switch branch: \(checkoutResult.output)"])))
                }
                return
            }

            print("Successfully switched to branch: \(branchName)")

            // If we stashed changes, restore them
            if stashCreated {
                let popResult = self.executeGitCommand(in: self.storedRepoPath, args: ["stash", "pop"])

                if popResult.failure {
                    // Stash pop failed - likely due to conflicts
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Switched branches, but couldn't reapply your changes due to conflicts. Run 'git stash pop' manually to resolve."])))
                    }
                    return
                }
                print("Restored stashed changes after branch switch")
            }

            // Refresh all status after switch
            DispatchQueue.main.async {
                self.refreshHandler {
                    completion(.success(()))
                }
            }
        }
    }

    func createBranch(branchName: String, fromBranch: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        // Validate branch name (basic validation)
        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Branch name cannot be empty"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Create branch from specified branch or current HEAD
            var args = ["checkout", "-b", trimmedName]
            if let fromBranch = fromBranch, !fromBranch.isEmpty {
                args.append(fromBranch)
            }

            let result = self.executeGitCommand(in: self.storedRepoPath, args: args)

            if result.failure {
                // Parse common error cases for friendly messages
                let output = result.output
                var friendlyMessage = "Failed to create branch"

                if output.contains("already exists") {
                    friendlyMessage = "Branch '\(trimmedName)' already exists"
                } else if output.contains("not a valid branch name") || output.contains("invalid ref format") {
                    friendlyMessage = "Invalid branch name"
                } else if output.contains("not found") || output.contains("does not exist") {
                    friendlyMessage = "Source branch not found"
                } else {
                    // Show a trimmed version of the error for unexpected cases
                    let errorSnippet = output.components(separatedBy: "\n").first ?? output
                    friendlyMessage = errorSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: friendlyMessage])))
                }
            } else {
                print("Successfully created and switched to branch: \(trimmedName)")
                // Refresh all status after creating branch
                DispatchQueue.main.async {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func mergeBranch(fromBranch: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Perform the merge
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["merge", fromBranch])

            if result.failure {
                // Check if it's a merge conflict
                if result.output.contains("CONFLICT") || result.output.contains("Automatic merge failed") {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Merge conflict! Please resolve manually."])))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to merge: \(result.output)"])))
                    }
                }
            } else {
                print("Successfully merged \(fromBranch) into current branch")
                // Refresh all status after merge
                DispatchQueue.main.async {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func deleteBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        // Don't allow deleting current branch
        if branchName == currentBranch {
            completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot delete the currently checked out branch"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Try to delete the branch locally first
            let localResult = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-D", branchName])

            let localBranchExists = !localResult.failure || !localResult.output.contains("not found")

            if localResult.failure, localBranchExists {
                // Local deletion failed for a reason other than "not found"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to delete local branch: \(localResult.output)"])))
                }
                return
            }

            if !localResult.failure {
                print("Successfully deleted local branch: \(branchName)")
            } else {
                print("Local branch '\(branchName)' doesn't exist, will delete from remote only")
            }

            // Also delete from remote (GitHub) if it exists there
            let remoteResult = self.executeGitCommand(in: self.storedRepoPath, args: ["push", "origin", "--delete", branchName])

            // Don't fail if remote deletion fails (branch might not exist on remote)
            if remoteResult.failure, !remoteResult.output.contains("remote ref does not exist") {
                print("Note: Could not delete from remote: \(remoteResult.output)")
            } else {
                print("Successfully deleted remote branch: \(branchName)")
            }

            // Explicitly refresh branch list to update UI immediately
            DispatchQueue.main.async {
                self.fetchBranches {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func renameBranch(oldName: String, newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "New branch name cannot be empty"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Rename branch (using -m)
            // If it's the current branch, we don't need to specify the old name, but providing it works too

            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-m", oldName, trimmedNewName])

            if result.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to rename branch: \(result.output)"])))
                }
            } else {
                print("Successfully renamed branch from \(oldName) to \(trimmedNewName)")
                DispatchQueue.main.async {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }
}
