//
//  GitBranchService.swift
//  GitMenuBar
//

import Combine
import Foundation

// swiftlint:disable type_body_length file_length

/// Owns branch-management state and git operations, extracted from `GitManager`
/// to keep that facade focused. `GitManager` pipes the published branch state
/// back to its own public facade so call sites are unchanged.
///
/// Threading mirrors `GitManager`: heavy git work runs on a background queue and
/// published state is written on the main thread via `DispatchQueue.main.async`
/// / `MainActor.run`, so the class itself is not actor-isolated.
final class GitBranchService: ObservableObject {
    @Published var currentBranch: String = "main"
    @Published var isAheadOfRemote: Bool = false
    @Published var remoteBranchName: String = ""
    @Published var behindCount: Int = 0
    @Published var isBehindRemote: Bool = false
    @Published var isRemoteAhead: Bool = false
    @Published var availableBranches: [String] = []
    @Published var branchInfos: [BranchInfo] = []
    @Published var defaultBranchName: String = "main"
    @Published var currentHash: String = ""
    @Published var isDetachedHead: Bool = false
    @Published var lastActiveBranch: String = ""

    private let repositoryContext: GitRepositoryContext
    private let commandRunner: GitCommandRunner

    /// Injected by `GitManager` so branch mutations can trigger a full app
    /// refresh (commit history, working tree, …) which lives outside this service.
    var refreshHandler: (@escaping () -> Void) -> Void

    init(repositoryContext: GitRepositoryContext, commandRunner: GitCommandRunner) {
        self.repositoryContext = repositoryContext
        self.commandRunner = commandRunner
        refreshHandler = { _ in }
    }

    private var storedRepoPath: String {
        repositoryContext.repositoryPath
    }

    private func runOnBackground<T>(_ operation: @escaping () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    private func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await GitExecution.publishOnMainActor(update)
    }

    private func executeGitCommand(
        in directory: String,
        args: [String],
        useAuth: Bool = false
    ) -> (output: String, failure: Bool) {
        GitExecution.executeGitCommand(
            in: directory,
            args: args,
            useAuth: useAuth,
            using: commandRunner
        )
    }

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

    func fetchLocalBranchesAsync() async -> [String] {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return [] }

        return await runOnBackground {
            let result = self.executeGitCommand(in: repositoryPath, args: ["branch", "--format=%(refname:short)"])
            guard !result.failure else { return [String]() }
            return result.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { $0 != "HEAD" }
        }
    }

    func fetchRemoteBranchesAsync() async -> [String] {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return [] }

        return await runOnBackground {
            let result = self.executeGitCommand(in: repositoryPath, args: ["branch", "-r", "--format=%(refname:short)"])
            guard !result.failure else { return [String]() }
            return result.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { $0 != "HEAD" && $0 != "origin/HEAD" }
                .compactMap { branch in
                    branch.hasPrefix("origin/") ? String(branch.dropFirst(7)) : nil
                }
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

    func getDefaultBranchNameAsync() async -> String {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return "main" }

        let detected: String? = await runOnBackground { () -> String? in
            let result = self.executeGitCommand(
                in: repositoryPath,
                args: ["symbolic-ref", "refs/remotes/origin/HEAD"]
            )
            if !result.failure, let last = result.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "/").last {
                return last
            }
            return nil
        }

        if let detected, !detected.isEmpty {
            await publishOnMainActor { self.defaultBranchName = detected }
            return detected
        }

        let fallback = await defaultBranchNameFallback()
        await publishOnMainActor { self.defaultBranchName = fallback }
        return fallback
    }

    private func defaultBranchNameFallback() async -> String {
        let repositoryPath = storedRepoPath
        let local = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["branch", "--format=%(refname:short)"]).output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if local.contains("main") {
            return "main"
        }
        if local.contains("master") {
            return "master"
        }
        return "main"
    }

    func resolveBranchInfoAsync() async -> [BranchInfo] {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return [] }

        let localBranches = await fetchLocalBranchesAsync()
        let remoteBranches = await fetchRemoteBranchesAsync()
        let currentBranch = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
                .output
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let infos = await runOnBackground {
            var result: [BranchInfo] = []

            for localName in localBranches {
                let trackingStatus = self.resolveTrackingStatus(
                    localName: localName,
                    currentBranch: currentBranch,
                    remoteBranches: remoteBranches
                )
                let lastCommitDate = self.lastCommitDate(for: localName, repositoryPath: repositoryPath)
                result.append(
                    BranchInfo(
                        name: localName,
                        isLocal: true,
                        isRemote: false,
                        isCurrent: localName == currentBranch,
                        trackingStatus: trackingStatus,
                        lastCommitDate: lastCommitDate
                    )
                )
            }

            let localSet = Set(localBranches)
            for remoteName in remoteBranches where !localSet.contains(remoteName) {
                let lastCommitDate = self.lastCommitDate(for: "origin/\(remoteName)", repositoryPath: repositoryPath)
                result.append(
                    BranchInfo(
                        name: remoteName,
                        isLocal: false,
                        isRemote: true,
                        isCurrent: false,
                        trackingStatus: .noRemote,
                        lastCommitDate: lastCommitDate
                    )
                )
            }

            return result
        }

        await publishOnMainActor {
            self.branchInfos = infos
        }

        return infos
    }

    /// Note: tracking-status resolution issues one synchronous git round-trip per
    /// local branch. Acceptable for typical repos; batch via a single `for-each-ref`
    /// if branch counts grow large.
    private func resolveTrackingStatus(
        localName: String,
        currentBranch _: String,
        remoteBranches: [String]
    ) -> BranchTrackingStatus {
        let repositoryPath = storedRepoPath
        let upstreamCheck = executeGitCommand(in: repositoryPath, args: ["rev-parse", "--verify", "--quiet", "\(localName)@{u}"])
        if upstreamCheck.failure {
            return .noRemote
        }

        let remoteRef = "origin/\(localName)"
        let remoteRefExists = !executeGitCommand(
            in: repositoryPath,
            args: ["show-ref", "--verify", "--quiet", "refs/remotes/\(remoteRef)"]
        ).failure
        if !remoteBranches.contains(localName), !remoteRefExists {
            return .noRemote
        }

        let counts = executeGitCommand(in: repositoryPath, args: ["rev-list", "--left-right", "--count", "\(remoteRef)...\(localName)"])
        guard !counts.failure else { return .unknown }
        let parts = counts.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespacesAndNewlines)
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else {
            return .unknown
        }

        if ahead == 0, behind == 0 {
            return .upToDate
        }
        if ahead > 0, behind == 0 {
            return .ahead(ahead)
        }
        if ahead == 0, behind > 0 {
            return .behind(behind)
        }
        return .diverged(ahead: ahead, behind: behind)
    }

    private func lastCommitDate(for ref: String, repositoryPath: String) -> Date? {
        let result = executeGitCommand(in: repositoryPath, args: ["log", "-1", "--format=%ct", ref])
        guard !result.failure else { return nil }
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timestamp = TimeInterval(trimmed) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
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

        if deleteLocal, featureBranch != currentBranch, featureBranch != defaultBranchName {
            let localResult = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["branch", "-D", featureBranch])
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

    private func hasUncommittedChanges() -> Bool {
        !executeGitCommand(in: storedRepoPath, args: ["status", "--porcelain"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
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
