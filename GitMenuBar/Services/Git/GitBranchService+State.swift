//
//  GitBranchService+State.swift
//  GitMenuBar
//

import Foundation

extension GitBranchService {
    func updateBranchInfo(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.currentBranch = "main"
                self.isAheadOfRemote = false
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Get current branch
            let branchResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])

            let branchName = branchResult.failure ? "main" : branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if ahead of remote using upstream tracking
            let revListResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "@{u}..HEAD"])

            var isAhead = false
            if revListResult.failure {
                // Fallback checks
                let revListMain = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/main"])
                if !revListMain.failure, let count = Int(revListMain.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    isAhead = count > 0
                } else {
                    let revListDefaultBranchFallback = self.executeGitCommand(
                        in: self.storedRepoPath,
                        args: ["rev-list", "--count", "HEAD", "^origin/master"]
                    )
                    let fallbackCount = Int(
                        revListDefaultBranchFallback.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    if !revListDefaultBranchFallback.failure, let fallbackCount {
                        isAhead = fallbackCount > 0
                    }
                }
            } else if let count = Int(revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                isAhead = count > 0
            }

            // Get current hash
            let hashResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "HEAD"])
            let hash = hashResult.failure ? "" : hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                self.isAheadOfRemote = isAhead
                self.currentHash = hash

                // Detect detached HEAD state
                if branchName == "HEAD" {
                    self.isDetachedHead = true
                    // Try to get a nicer name like (detached at <short_hash>)
                    let shortHashResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "--short", "HEAD"])
                    if !shortHashResult.failure {
                        self.currentBranch = "(detached at \(shortHashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)))"
                    } else {
                        self.currentBranch = "(detached)"
                    }
                } else {
                    self.isDetachedHead = false
                    self.currentBranch = branchName
                    self.lastActiveBranch = branchName
                }

                completion?()
            }
        }
    }

    func updateBranchInfoAsync() async {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
                self.currentBranch = "main"
                self.isAheadOfRemote = false
                self.currentHash = ""
                self.isDetachedHead = false
            }
            return
        }

        let snapshot = await runOnBackground {
            let branchResult = self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
            let branchName = branchResult.failure ? "main" : branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            let revListResult = self.executeGitCommand(in: repositoryPath, args: ["rev-list", "--count", "@{u}..HEAD"])

            var isAhead = false
            if revListResult.failure {
                let revListMain = self.executeGitCommand(in: repositoryPath, args: ["rev-list", "--count", "HEAD", "^origin/main"])
                if !revListMain.failure, let count = Int(revListMain.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    isAhead = count > 0
                } else {
                    let revListDefaultBranchFallback = self.executeGitCommand(
                        in: repositoryPath,
                        args: ["rev-list", "--count", "HEAD", "^origin/master"]
                    )
                    let fallbackCount = Int(revListDefaultBranchFallback.output.trimmingCharacters(in: .whitespacesAndNewlines))
                    if !revListDefaultBranchFallback.failure, let fallbackCount {
                        isAhead = fallbackCount > 0
                    }
                }
            } else if let count = Int(revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                isAhead = count > 0
            }

            let hashResult = self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "HEAD"])
            let hash = hashResult.failure ? "" : hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            let detachedBranchName: String
            let isDetachedHead = branchName == "HEAD"
            if isDetachedHead {
                let shortHashResult = self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--short", "HEAD"])
                detachedBranchName = shortHashResult.failure
                    ? "(detached)"
                    : "(detached at \(shortHashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)))"
            } else {
                detachedBranchName = branchName
            }

            return (
                branchName: detachedBranchName,
                activeBranchName: branchName,
                isAhead: isAhead,
                currentHash: hash,
                isDetachedHead: isDetachedHead
            )
        }

        await publishOnMainActor {
            self.currentBranch = snapshot.branchName
            self.isAheadOfRemote = snapshot.isAhead
            self.currentHash = snapshot.currentHash
            self.isDetachedHead = snapshot.isDetachedHead
            if !snapshot.isDetachedHead {
                self.lastActiveBranch = snapshot.activeBranchName
            }
        }
    }

    func fetchBranches(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.availableBranches = []
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Get all branches (local and remote)
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-a", "--format=%(refname:short)"])

            if !result.failure {
                var branches = result.output
                    .components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                    .map { branch in
                        // Clean up remote branch names
                        if branch.hasPrefix("origin/") {
                            return String(branch.dropFirst(7)) // Remove "origin/"
                        }
                        return branch
                    }
                    .filter { $0 != "HEAD" && $0 != "origin" && !$0.contains("origin/HEAD") } // Remove HEAD and confusing origin entries

                // Remove duplicates (local + remote same branch)
                branches = Array(Set(branches)).sorted()

                DispatchQueue.main.async {
                    self.availableBranches = branches
                    completion?()
                }
            } else {
                DispatchQueue.main.async {
                    self.availableBranches = []
                    completion?()
                }
            }
        }
    }

    func fetchBranchesAsync() async {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
                self.availableBranches = []
            }
            return
        }

        let branches = await runOnBackground {
            let result = self.executeGitCommand(in: repositoryPath, args: ["branch", "-a", "--format=%(refname:short)"])
            guard !result.failure else {
                return [String]()
            }

            return Array(
                Set(
                    result.output
                        .components(separatedBy: .newlines)
                        .filter { !$0.isEmpty }
                        .map { branch in
                            branch.hasPrefix("origin/") ? String(branch.dropFirst(7)) : branch
                        }
                        .filter { $0 != "HEAD" && $0 != "origin" && !$0.contains("origin/HEAD") }
                )
            ).sorted()
        }

        await publishOnMainActor {
            self.availableBranches = branches
        }
    }

    func checkRemoteStatus(completion: (() -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            await checkRemoteStatusAsync()
            await publishOnMainActor {
                completion?()
            }
        }
    }

    func checkRemoteStatusAsync() async {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
                self.isRemoteAhead = false
                self.isBehindRemote = false
                self.behindCount = 0
            }
            return
        }

        let snapshot = await runOnBackground {
            _ = self.executeGitCommand(in: repositoryPath, args: ["fetch"], useAuth: true)
            let result = self.executeGitCommand(in: repositoryPath, args: ["rev-list", "--left-right", "--count", "@{u}...HEAD"])

            guard !result.failure else {
                return (behindCount: 0, isRemoteAhead: false, isBehindRemote: false)
            }

            let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
            guard parts.count == 2 else {
                return (behindCount: 0, isRemoteAhead: false, isBehindRemote: false)
            }

            let behind = Int(parts[0]) ?? 0
            return (behindCount: behind, isRemoteAhead: behind > 0, isBehindRemote: behind > 0)
        }

        await publishOnMainActor {
            self.behindCount = snapshot.behindCount
            self.isRemoteAhead = snapshot.isRemoteAhead
            self.isBehindRemote = snapshot.isBehindRemote
        }
    }
}
