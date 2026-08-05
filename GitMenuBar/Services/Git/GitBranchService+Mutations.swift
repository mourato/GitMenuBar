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
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to delete remote branch '\(branchName)': \(result.output)"
                ]
            ))
        }
        return .success(())
    }

    func createBranchFromCurrentHead(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(branchError(code: 1, description: "No repository path configured")))
            return
        }

        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(branchError(code: 2, description: "Branch name cannot be empty")))
            return
        }

        Task {
            let repositoryPath = storedRepoPath
            let result = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["checkout", "-b", trimmedName])
            }

            if result.failure {
                await publishOnMainActor {
                    completion(.failure(self.branchError(
                        code: 3,
                        description: "Failed to create branch: \(result.output)"
                    )))
                }
            } else {
                print("Successfully created and switched to branch \(trimmedName)")
                await publishOnMainActor {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func switchBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(branchError(code: 1, description: "No repository path configured")))
            return
        }

        Task {
            let repositoryPath = storedRepoPath
            // Check if we have uncommitted changes
            let statusResult = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["status", "--porcelain"])
            }
            let hasChanges = !statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            var stashCreated = false

            // If we have changes, stash them first
            if hasChanges {
                let stashResult = await runOnBackground {
                    self.executeGitCommand(
                        in: repositoryPath,
                        args: ["stash", "push", "-u", "-m", "GitMenuBar auto-stash for branch switch"]
                    )
                }

                if stashResult.failure {
                    await publishOnMainActor {
                        completion(.failure(self.branchError(
                            code: 2,
                            description: "Failed to save changes: \(stashResult.output)"
                        )))
                    }
                    return
                }
                stashCreated = true
                print("Stashed changes before switching branches")
            }

            // Try to switch/checkout branch
            let checkoutResult = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["checkout", branchName])
            }

            if checkoutResult.failure {
                // If checkout failed and we stashed, try to restore the stash
                if stashCreated {
                    _ = await runOnBackground {
                        self.executeGitCommand(in: repositoryPath, args: ["stash", "pop"])
                    }
                }
                await publishOnMainActor {
                    completion(.failure(self.branchError(
                        code: 3,
                        description: "Failed to switch branch: \(checkoutResult.output)"
                    )))
                }
                return
            }

            print("Successfully switched to branch: \(branchName)")

            // If we stashed changes, restore them
            if stashCreated {
                let popResult = await runOnBackground {
                    self.executeGitCommand(in: repositoryPath, args: ["stash", "pop"])
                }

                if popResult.failure {
                    // Stash pop failed - likely due to conflicts
                    await publishOnMainActor {
                        completion(.failure(self.branchError(
                            code: 4,
                            description: "Switched branches, but couldn't reapply your changes due to conflicts. "
                                + "Run 'git stash pop' manually to resolve."
                        )))
                    }
                    return
                }
                print("Restored stashed changes after branch switch")
            }

            // Refresh all status after switch
            await publishOnMainActor {
                self.refreshHandler {
                    completion(.success(()))
                }
            }
        }
    }

    func createBranch(branchName: String, fromBranch: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(branchError(code: 1, description: "No repository path configured")))
            return
        }

        // Validate branch name (basic validation)
        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(branchError(code: 2, description: "Branch name cannot be empty")))
            return
        }

        Task {
            let repositoryPath = storedRepoPath
            // Create branch from specified branch or current HEAD
            let args = {
                var args = ["checkout", "-b", trimmedName]
                if let fromBranch, !fromBranch.isEmpty {
                    args.append(fromBranch)
                }
                return args
            }()

            let result = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: args)
            }

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

                await publishOnMainActor {
                    completion(.failure(self.branchError(code: 3, description: friendlyMessage)))
                }
            } else {
                print("Successfully created and switched to branch: \(trimmedName)")
                // Refresh all status after creating branch
                await publishOnMainActor {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func mergeBranch(fromBranch: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(branchError(code: 1, description: "No repository path configured")))
            return
        }

        Task {
            let repositoryPath = storedRepoPath
            // Perform the merge
            let result = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["merge", fromBranch])
            }

            if result.failure {
                // Check if it's a merge conflict
                if result.output.contains("CONFLICT") || result.output.contains("Automatic merge failed") {
                    await publishOnMainActor {
                        completion(.failure(self.branchError(
                            code: 4,
                            description: "Merge conflict! Please resolve manually."
                        )))
                    }
                } else {
                    await publishOnMainActor {
                        completion(.failure(self.branchError(
                            code: 3,
                            description: "Failed to merge: \(result.output)"
                        )))
                    }
                }
            } else {
                print("Successfully merged \(fromBranch) into current branch")
                // Refresh all status after merge
                await publishOnMainActor {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func deleteBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(branchError(code: 1, description: "No repository path configured")))
            return
        }

        // Don't allow deleting current branch
        if branchName == currentBranch {
            completion(.failure(branchError(
                code: 2,
                description: "Cannot delete the currently checked out branch"
            )))
            return
        }

        Task {
            let repositoryPath = storedRepoPath
            // Try to delete the branch locally first
            let localResult = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["branch", "--delete", branchName])
            }

            if localResult.failure {
                await publishOnMainActor {
                    completion(.failure(self.branchError(
                        code: 3,
                        description: "Failed to delete local branch: \(localResult.output)"
                    )))
                }
                return
            }

            print("Successfully deleted local branch: \(branchName)")

            // Explicitly refresh branch list to update UI immediately
            await publishOnMainActor {
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
            completion(.failure(branchError(code: 1, description: "No repository path configured")))
            return
        }

        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty else {
            completion(.failure(branchError(code: 2, description: "New branch name cannot be empty")))
            return
        }

        Task {
            let repositoryPath = storedRepoPath
            // Rename branch (using -m)
            // If it's the current branch, we don't need to specify the old name, but providing it works too

            let result = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["branch", "-m", oldName, trimmedNewName])
            }

            if result.failure {
                await publishOnMainActor {
                    completion(.failure(self.branchError(
                        code: 3,
                        description: "Failed to rename branch: \(result.output)"
                    )))
                }
            } else {
                print("Successfully renamed branch from \(oldName) to \(trimmedNewName)")
                await publishOnMainActor {
                    self.refreshHandler {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    private func branchError(code: Int, description: String) -> NSError {
        NSError(
            domain: "GitManager",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
