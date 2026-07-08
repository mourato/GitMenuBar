//
//  GitBranchService+MergeToDefault.swift
//  GitMenuBar
//

import Foundation

extension GitBranchService {
    /// Merges `featureBranch` into the detected default branch *without* deleting
    /// anything. Stashes uncommitted work, switches to the default branch, merges,
    /// then restores the stash. Cleanup is a separate, explicit step via
    /// ``cleanupMergedBranchAsync(featureBranch:cleanupOption:)`` so the user is
    /// never forced to pick a destructive option just to merge.
    ///
    /// State is refreshed through `refreshHandler` (the same hook used by every
    /// other branch mutation) so the rest of the app stays in sync.
    func mergeFeatureIntoDefaultAsync(
        featureBranch: String
    ) async -> Result<MergeToDefaultResult, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        // 1. Detect default branch
        let defaultBranch = await getDefaultBranchNameAsync()

        // 2. Check for uncommitted changes and stash if needed
        let hasChanges = hasUncommittedChanges()
        var stashed = false
        if hasChanges {
            let stashResult = await runOnBackground {
                self.executeGitCommand(
                    in: repositoryPath,
                    args: ["stash", "push", "-u", "-m", "GitMenuBar auto-stash for merge"]
                )
            }
            guard !stashResult.failure else {
                return .failure(NSError(
                    domain: "GitManager",
                    code: 20,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to stash changes: \(stashResult.output)"]
                ))
            }
            stashed = true
        }

        // 3. Switch to default branch
        let currentWasDefault = currentBranch == defaultBranch
        if !currentWasDefault {
            _ = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["checkout", defaultBranch])
            }
        }

        // 4. Merge feature branch
        let mergeResult = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["merge", featureBranch])
        }
        guard !mergeResult.failure else {
            // On failure, switch back and restore the stash.
            if !currentWasDefault {
                _ = await runOnBackground {
                    self.executeGitCommand(in: repositoryPath, args: ["checkout", self.currentBranch])
                }
            }
            if stashed {
                _ = await runOnBackground {
                    self.executeGitCommand(in: repositoryPath, args: ["stash", "pop"])
                }
            }
            let isConflict = mergeResult.output.contains("CONFLICT")
                || mergeResult.output.contains("Automatic merge failed")
            return .failure(NSError(
                domain: "GitManager",
                code: 21,
                userInfo: [
                    NSLocalizedDescriptionKey: isConflict
                        ? "Merge conflict! Please resolve manually."
                        : "Merge failed: \(mergeResult.output)"
                ]
            ))
        }

        // 5. Restore stash if needed
        if stashed {
            _ = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["stash", "pop"])
            }
        }

        // 6. Refresh app state through the canonical hook.
        refreshHandler {}

        return .success(MergeToDefaultResult(
            didSwitchToDefault: !currentWasDefault,
            didMerge: true,
            didDeleteLocal: false,
            didDeleteRemote: false,
            defaultBranchName: defaultBranch,
            featureBranchName: featureBranch
        ))
    }

    /// Deletes an *already merged* feature branch locally and/or remotely per
    /// `cleanupOption`. Intended to run after ``mergeFeatureIntoDefaultAsync``,
    /// when the current branch is the default and the feature branch is safely
    /// merged. Never re-merges.
    ///
    /// State is refreshed through `refreshHandler` so the rest of the app stays
    /// in sync.
    func cleanupMergedBranchAsync(
        featureBranch: String,
        cleanupOption: BranchCleanupOption
    ) async -> Result<MergeToDefaultResult, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let deleteLocal: Bool
        let deleteRemote: Bool
        switch cleanupOption {
        case .deleteLocal:
            deleteLocal = true; deleteRemote = false
        case .deleteLocalAndRemote:
            deleteLocal = true; deleteRemote = true
        case .deleteRemoteOnly:
            deleteLocal = false; deleteRemote = true
        case .keep:
            deleteLocal = false; deleteRemote = false
        }

        var didDeleteLocal = false
        var didDeleteRemote = false

        if deleteLocal {
            guard featureBranch != currentBranch, featureBranch != defaultBranchName else {
                return .failure(mergeCleanupError(
                    code: 22,
                    description: "Cannot delete the current or default branch."
                ))
            }

            let localResult = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["branch", "-D", featureBranch])
            }
            guard !localResult.failure else {
                return .failure(mergeCleanupError(
                    code: 23,
                    description: "Failed to delete local branch '\(featureBranch)': \(localResult.output)"
                ))
            }
            didDeleteLocal = !localResult.failure
        }

        if deleteRemote {
            let remoteResult = await runOnBackground {
                self.executeGitCommand(
                    in: repositoryPath,
                    args: ["push", "origin", "--delete", featureBranch],
                    useAuth: true
                )
            }
            guard !remoteResult.failure else {
                refreshHandler {}
                return .failure(mergeCleanupError(
                    code: 24,
                    description: "Failed to delete remote branch '\(featureBranch)': \(remoteResult.output)"
                ))
            }
            didDeleteRemote = !remoteResult.failure
        }

        refreshHandler {}

        return .success(MergeToDefaultResult(
            didSwitchToDefault: false,
            didMerge: false,
            didDeleteLocal: didDeleteLocal,
            didDeleteRemote: didDeleteRemote,
            defaultBranchName: defaultBranchName,
            featureBranchName: featureBranch
        ))
    }

    private func mergeCleanupError(code: Int, description: String) -> NSError {
        NSError(
            domain: "GitManager",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    private func hasUncommittedChanges() -> Bool {
        !executeGitCommand(in: storedRepoPath, args: ["status", "--porcelain"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}
