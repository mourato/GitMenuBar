//
//  GitBranchService+State.swift
//  GitMenuBar
//

import Foundation

extension GitBranchService {
    func updateBranchInfo(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            currentBranch = "main"
            isAheadOfRemote = false
            completion?()
            return
        }

        Task { @MainActor in
            let repositoryPath = storedRepoPath
            // Get current branch
            let branchResult = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
            }

            let branchName = branchResult.failure ? "main" : branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            let aheadCount = await runOnBackground {
                self.trackingAheadCount(repositoryPath: repositoryPath)
            }

            // Get current hash
            let hashResult = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "HEAD"])
            }
            let hash = hashResult.failure ? "" : hashResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            self.isAheadOfRemote = aheadCount > 0
            self.currentHash = hash

            // Detect detached HEAD state
            if branchName == "HEAD" {
                self.isDetachedHead = true
                // Try to get a nicer name like (detached at <short_hash>)
                let shortHashResult = await runOnBackground {
                    self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--short", "HEAD"])
                }
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

    func updateBranchInfoAsync() async {
        _ = await updateBranchInfoAsync(session: nil)
    }

    func updateBranchInfoAsync(session: GitRefreshSession?) async -> Int {
        let repositoryPath = session?.repositoryPath ?? storedRepoPath
        guard !repositoryPath.isEmpty else {
            await GitExecution.publishOnMainActor(ifCurrent: session) {
                self.currentBranch = "main"
                self.isAheadOfRemote = false
                self.currentHash = ""
                self.isDetachedHead = false
            }
            return 0
        }

        let snapshot = await runOnBackground {
            let branchResult = self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
            let branchName = branchResult.failure ? "main" : branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            let aheadCount = self.trackingAheadCount(repositoryPath: repositoryPath)

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
                isAhead: aheadCount > 0,
                aheadCount: aheadCount,
                currentHash: hash,
                isDetachedHead: isDetachedHead
            )
        }

        await GitExecution.publishOnMainActor(ifCurrent: session) {
            self.currentBranch = snapshot.branchName
            self.isAheadOfRemote = snapshot.isAhead
            self.currentHash = snapshot.currentHash
            self.isDetachedHead = snapshot.isDetachedHead
            if !snapshot.isDetachedHead {
                self.lastActiveBranch = snapshot.activeBranchName
            }
        }
        return snapshot.aheadCount
    }

    private nonisolated func trackingAheadCount(repositoryPath: String) -> Int {
        let result = executeGitCommand(in: repositoryPath, args: ["rev-list", "--count", "@{u}..HEAD"])
        if !result.failure, let count = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return count
        }

        for branch in ["main", "master"] {
            let fallback = executeGitCommand(in: repositoryPath, args: ["rev-list", "--count", "HEAD", "^origin/\(branch)"])
            if !fallback.failure, let count = Int(fallback.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return count
            }
        }
        return 0
    }

    func fetchBranches(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            availableBranches = []
            completion?()
            return
        }

        Task { @MainActor in
            let repositoryPath = storedRepoPath
            // Get all branches (local and remote)
            let result = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["branch", "-a", "--format=%(refname:short)"])
            }

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

                self.availableBranches = branches
                completion?()
            } else {
                self.availableBranches = []
                completion?()
            }
        }
    }

    func fetchBranchesAsync() async {
        await fetchBranchesAsync(session: nil)
    }

    func fetchBranchesAsync(session: GitRefreshSession?) async {
        let repositoryPath = session?.repositoryPath ?? storedRepoPath
        guard !repositoryPath.isEmpty else {
            await GitExecution.publishOnMainActor(ifCurrent: session) {
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

        await GitExecution.publishOnMainActor(ifCurrent: session) {
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
        await checkRemoteStatusAsync(session: nil)
    }

    func checkRemoteStatusAsync(session: GitRefreshSession?) async {
        let repositoryPath = session?.repositoryPath ?? storedRepoPath
        guard !repositoryPath.isEmpty else {
            await GitExecution.publishOnMainActor(ifCurrent: session) {
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

        await GitExecution.publishOnMainActor(ifCurrent: session) {
            self.behindCount = snapshot.behindCount
            self.isRemoteAhead = snapshot.isRemoteAhead
            self.isBehindRemote = snapshot.isBehindRemote
        }
    }
}
