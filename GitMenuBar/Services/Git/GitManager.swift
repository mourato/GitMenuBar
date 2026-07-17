//
//  GitManager.swift
//  GitMenuBar
//

import AppKit
import Combine
import Foundation

// swiftlint:disable type_body_length file_length
class GitManager: ObservableObject {
    private struct RepositoryWipeError: Error {
        let code: Int
        let description: String
    }

    @Published var commitCount: Int = 0
    @Published var isCommitting: Bool = false
    @Published var uncommittedFiles: [String] = []
    @Published var stagedFiles: [WorkingTreeFile] = []
    @Published var changedFiles: [WorkingTreeFile] = []
    @Published var currentBranch: String = "main"
    @Published var isAheadOfRemote: Bool = false
    @Published var remoteUrl: String = ""
    @Published var commitHistory: [Commit] = []
    @Published var isDetachedHead: Bool = false
    @Published var currentHash: String = ""
    @Published var lastActiveBranch: String = ""
    @Published var worktreeSnapshot: GitWorktreeSnapshot?
    @Published var availableBranches: [String] = []
    @Published var branchInfos: [BranchInfo] = []
    @Published var defaultBranchName: String = "main"
    @Published var isRemoteAhead: Bool = false
    @Published var isBehindRemote: Bool = false
    @Published var remoteBranchName: String = ""
    @Published var behindCount: Int = 0
    @Published var isPrivate: Bool = false
    @Published private(set) var commitHistoryLimit = 25

    /// Token provider for authenticated git operations (push/pull)
    var tokenProvider: (() -> String?)? {
        didSet {
            commandRunner.tokenProvider = tokenProvider
        }
    }

    /// GitHub API client for checking repo existence
    var githubAPIClient: GitHubAPIClient?

    private let repositoryContext: GitRepositoryContext
    private let commandRunner: GitCommandRunner
    private let workingTreeParser: WorkingTreeParser
    let branchService: GitBranchService
    let atomicCommitService: GitAtomicCommitService
    let commitHistoryService: GitCommitHistoryService

    init(repositoryPathOverride: String? = nil) {
        repositoryContext = GitRepositoryContext(overridePath: repositoryPathOverride)
        commandRunner = GitCommandRunner()
        workingTreeParser = WorkingTreeParser(runner: commandRunner)
        let branchService = GitBranchService(
            repositoryContext: repositoryContext,
            commandRunner: commandRunner
        )
        self.branchService = branchService
        atomicCommitService = GitAtomicCommitService(
            repositoryContext: repositoryContext,
            commandRunner: commandRunner
        )
        commitHistoryService = GitCommitHistoryService(
            repositoryContext: repositoryContext,
            commandRunner: commandRunner
        )
        self.branchService.refreshHandler = { [weak self] block in
            self?.refresh(completion: block)
        }
        pipeBranchServiceState()
        pipeCommitHistoryServiceState()
        updateLocalCommitCount()
        updateUncommittedFiles()
        updateBranchInfo()
        updateRemoteUrl()
        commitHistoryService.fetchCommitHistory(includeReflog: false)
        fetchBranches()
    }

    private func pipeBranchServiceState() {
        branchService.$currentBranch.assign(to: &$currentBranch)
        branchService.$isAheadOfRemote.assign(to: &$isAheadOfRemote)
        branchService.$remoteBranchName.assign(to: &$remoteBranchName)
        branchService.$behindCount.assign(to: &$behindCount)
        branchService.$isBehindRemote.assign(to: &$isBehindRemote)
        branchService.$isRemoteAhead.assign(to: &$isRemoteAhead)
        branchService.$availableBranches.assign(to: &$availableBranches)
        branchService.$branchInfos.assign(to: &$branchInfos)
        branchService.$defaultBranchName.assign(to: &$defaultBranchName)
        branchService.$currentHash.assign(to: &$currentHash)
        branchService.$isDetachedHead.assign(to: &$isDetachedHead)
        branchService.$lastActiveBranch.assign(to: &$lastActiveBranch)
        branchService.$worktreeSnapshot.assign(to: &$worktreeSnapshot)
    }

    private func pipeCommitHistoryServiceState() {
        commitHistoryService.$commitHistory.assign(to: &$commitHistory)
        commitHistoryService.$commitHistoryLimit.assign(to: &$commitHistoryLimit)
    }

    private var storedRepoPath: String {
        get { repositoryContext.repositoryPath }
        set { repositoryContext.repositoryPath = newValue }
    }

    private func runOnBackground<T>(_ operation: @escaping () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    private func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await GitExecution.publishOnMainActor(update)
    }

    private func makeMissingRepositoryError() -> NSError {
        GitExecution.missingRepositoryError()
    }

    var canLoadMoreCommitHistory: Bool {
        commitHistoryService.canLoadMoreCommitHistory
    }

    func refreshAsync(includeReflogHistory: Bool? = nil) async {
        await updateLocalCommitCountAsync()
        await updateUncommittedFilesAsync()
        await updateBranchInfoAsync()
        await updateRemoteUrlAsync()
        await fetchCommitHistoryAsync(includeReflog: includeReflogHistory)
        await fetchBranchesAsync()
        await resolveBranchInfoAsync()
        await getDefaultBranchNameAsync()
        await checkRemoteStatusAsync()
        await checkRepoVisibilityAsync()
    }

    func refresh(
        includeReflogHistory: Bool? = nil,
        completion: (() -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            await refreshAsync(includeReflogHistory: includeReflogHistory)
            await publishOnMainActor {
                completion?()
            }
        }
    }

    func commitLocallyAsync(
        _ message: String,
        skipUIUpdates: Bool = false
    ) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(makeMissingRepositoryError())
        }

        await publishOnMainActor {
            self.isCommitting = true
        }

        let result: Result<Void, Error> = await runOnBackground {
            let commitResult = self.executeGitCommand(
                in: repositoryPath,
                args: ["commit", "--no-gpg-sign", "--allow-empty-message", "--cleanup=verbatim", "-m", message]
            )

            guard !commitResult.failure else {
                return .failure(
                    NSError(
                        domain: "GitManager",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create commit: \(commitResult.output)"]
                    )
                )
            }

            return .success(())
        }

        await publishOnMainActor {
            self.isCommitting = false
        }

        if case .success = result, !skipUIUpdates {
            await updateLocalCommitCountAsync()
            await updateUncommittedFilesAsync()
            await updateBranchInfoAsync()
        }

        return result
    }

    // MARK: - Atomic Commits

    /// Returns a map of changed file path -> diff string for all changed files.
    func diffForChangedFilesAsync() async -> [String: String] {
        await atomicCommitService.diffForChangedFilesAsync(changedFiles: changedFiles)
    }

    /// Stage specific files and commit with the given message.
    func commitAtomicGroupAsync(
        files: [String],
        message: String
    ) async -> Result<Void, Error> {
        await atomicCommitService.commitAtomicGroupAsync(files: files, message: message)
    }

    /// Execute the full atomic commit sequence for a list of groups.
    func performAtomicCommitsAsync(
        groups: [AtomicCommitGroup]
    ) async -> Result<Void, Error> {
        await updateUncommittedFilesAsync()
        let result = await atomicCommitService.performAtomicCommitsAsync(
            groups: groups,
            changedFiles: changedFiles,
            stagedFiles: stagedFiles,
            uncommittedFiles: uncommittedFiles
        )
        await refreshAsync()
        return result
    }

    func commitLocally(
        _ message: String,
        skipUIUpdates: Bool = false,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            let result = await commitLocallyAsync(message, skipUIUpdates: skipUIUpdates)
            await publishOnMainActor {
                completion?(result)
            }
        }
    }

    func commitLocallyWithFallbackAsync(
        _ message: String,
        skipUIUpdates: Bool = false
    ) async -> Result<Void, Error> {
        await updateUncommittedFilesAsync()
        let shouldAutoStage = stagedFiles.isEmpty && !changedFiles.isEmpty

        if shouldAutoStage {
            let stageResult = await stageAllChangesAsync()
            guard case .success = stageResult else {
                return stageResult
            }
        }

        return await commitLocallyAsync(message, skipUIUpdates: skipUIUpdates)
    }

    func commitLocallyWithFallback(
        _ message: String,
        skipUIUpdates: Bool = false,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            let result = await commitLocallyWithFallbackAsync(message, skipUIUpdates: skipUIUpdates)
            await publishOnMainActor {
                completion?(result)
            }
        }
    }

    // MARK: - Repository Initialization

    func isGitRepository(at path: String) -> Bool {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: gitPath)
    }

    func hasRemoteConfigured(at path: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["config", "--get", "remote.origin.url"])
        return !result.failure && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check if the remote repository actually exists on GitHub
    func remoteRepositoryExists(at path: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // First check if remote is configured.
            let remoteConfigResult = self.executeGitCommand(in: path, args: ["config", "--get", "remote.origin.url"])
            guard !remoteConfigResult.failure else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            let remoteURL = remoteConfigResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remoteURL.isEmpty else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            // Parse owner and repo from URL.
            // Supports formats like:
            // - https://github.com/owner/repo
            // - https://github.com/owner/repo.git
            // - git@github.com:owner/repo.git
            guard let reference = GitHubRemoteURLParser.parse(remoteURL) else {
                DispatchQueue.main.async {
                    completion(true)
                }
                return
            }

            // Check if repo exists using GitHub API.
            guard let apiClient = self.githubAPIClient else {
                DispatchQueue.main.async {
                    completion(true)
                }
                return
            }

            Task {
                let exists = await apiClient.checkRepositoryURLExists(
                    owner: reference.owner,
                    repo: reference.repository
                )
                DispatchQueue.main.async {
                    completion(exists)
                }
            }
        }
    }

    func initializeRepository(at path: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["init"])
        if result.failure {
            print("Error initializing repository: \(result.output)")
            return false
        }
        print("Initialized git repository at: \(path)")
        return true
    }

    func createInitialCommit(at path: String, message: String) -> Bool {
        // Stage all files
        let addResult = executeGitCommand(in: path, args: ["add", "."])
        if addResult.failure {
            print("Error staging files: \(addResult.output)")
            return false
        }

        // Create initial commit
        let commitResult = executeGitCommand(in: path, args: ["commit", "--no-gpg-sign", "-m", message])
        if commitResult.failure {
            print("Error creating initial commit: \(commitResult.output)")
            return false
        }

        print("Created initial commit: \(message)")
        return true
    }

    func addRemote(at path: String, url: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["remote", "add", "origin", url])
        if result.failure {
            print("Error adding remote: \(result.output)")
            return false
        }
        print("Added remote origin: \(url)")
        return true
    }

    func hasUncommittedChanges(at path: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["status", "--porcelain"])
        return !result.failure && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateRemoteURL(at path: String, newURL: String) -> Bool {
        let result = executeGitCommand(in: path, args: ["remote", "set-url", "origin", newURL])
        return !result.failure
    }

    func pushToNewRemote(at path: String) -> Bool {
        // Push with --set-upstream for new branch
        let result = executeGitCommand(in: path, args: ["push", "-u", "origin", "main"], useAuth: true)
        if result.failure {
            print("Error pushing to remote: \(result.output)")
            return false
        }
        print("Successfully pushed to remote")
        return true
    }

    func pushToRemote(completion: ((Result<Void, Error>) -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            let result = await pushToRemoteAsync()
            await publishOnMainActor {
                completion?(result)
            }
        }
    }

    func pushToRemoteAsync() async -> Result<Void, Error> {
        await pushToBranchAsync(branchName: currentBranch, force: false)
    }

    func pushToBranch(branchName: String, force: Bool, completion: ((Result<Void, Error>) -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            let result = await pushToBranchAsync(branchName: branchName, force: force)
            await publishOnMainActor {
                completion?(result)
            }
        }
    }

    func pushToBranchAsync(branchName: String, force: Bool) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        let currentBranchName = currentBranch

        guard !repositoryPath.isEmpty else {
            let error = NSError(
                domain: "GitManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Error: No repository path configured"]
            )
            print(error.localizedDescription)
            return .failure(error)
        }

        return await runOnBackground {
            var pushArgs: [String]

            if branchName == currentBranchName {
                pushArgs = force ? ["push", "--force", "-u", "origin", branchName] : ["push", "-u", "origin", branchName]
            } else {
                pushArgs = force ? ["push", "--force", "origin", "HEAD:\(branchName)"] : ["push", "origin", "HEAD:\(branchName)"]
            }

            let pushResult = self.executeGitCommand(in: repositoryPath, args: pushArgs, useAuth: true)
            if pushResult.failure {
                if pushResult.output.contains("rejected") || pushResult.output.contains("diverged") || pushResult.output.contains("non-fast-forward") {
                    let forcePushArgs = branchName == currentBranchName
                        ? ["push", "--force", "-u", "origin", branchName]
                        : ["push", "--force", "origin", "HEAD:\(branchName)"]
                    let forcePushResult = self.executeGitCommand(in: repositoryPath, args: forcePushArgs, useAuth: true)

                    guard !forcePushResult.failure else {
                        let error = NSError(
                            domain: "GitManager",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Error force pushing: \(forcePushResult.output)"]
                        )
                        print(error.localizedDescription)
                        return .failure(error)
                    }

                    print("Successfully force pushed commits to remote")
                    return .success(())
                }

                let error = NSError(
                    domain: "GitManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Error pushing: \(pushResult.output)"]
                )
                print(error.localizedDescription)
                return .failure(error)
            }

            print("Successfully pushed commits to remote")
            return .success(())
        }
    }

    func updateRemoteUrl() {
        Task { [weak self] in
            await self?.updateRemoteUrlAsync()
        }
    }

    func updateRemoteUrlAsync() async {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
                self.remoteUrl = ""
            }
            return
        }

        let remoteURL = await runOnBackground {
            let result = self.executeGitCommand(in: repositoryPath, args: ["config", "--get", "remote.origin.url"])
            guard !result.failure else {
                return ""
            }
            return GitHubRemoteURLParser.normalizedWebURL(from: result.output)
        }

        await publishOnMainActor {
            self.remoteUrl = remoteURL
        }
    }

    func updateLocalCommitCount(completion: (() -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            await updateLocalCommitCountAsync()
            await publishOnMainActor {
                completion?()
            }
        }
    }

    func updateLocalCommitCountAsync() async {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
                self.commitCount = 0
            }
            return
        }

        let count = await runOnBackground {
            let revListResult = self.executeGitCommand(in: repositoryPath, args: ["rev-list", "--count", "@{u}..HEAD"])

            if revListResult.failure {
                let revListFallback = self.executeGitCommand(in: repositoryPath, args: ["rev-list", "--count", "HEAD", "^origin/main"])
                if let count = Int(revListFallback.output.trimmingCharacters(in: .whitespacesAndNewlines)), !revListFallback.failure {
                    return count
                }

                let revListDefaultBranchFallback = self.executeGitCommand(
                    in: repositoryPath,
                    args: ["rev-list", "--count", "HEAD", "^origin/master"]
                )
                return Int(revListDefaultBranchFallback.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }

            return Int(revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        await publishOnMainActor {
            self.commitCount = count
        }
    }

    func updateUncommittedFiles(completion: (() -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            await updateUncommittedFilesAsync()
            await publishOnMainActor {
                completion?()
            }
        }
    }

    func updateUncommittedFilesAsync() async {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
                self.uncommittedFiles = []
                self.stagedFiles = []
                self.changedFiles = []
            }
            return
        }

        let snapshot = await runOnBackground {
            let statusResult = self.executeGitCommand(in: repositoryPath, args: ["status", "--porcelain", "-uall"])

            guard !statusResult.failure else {
                print("Error getting git status: \(statusResult.output)")
                return (
                    stagedFiles: [WorkingTreeFile](),
                    changedFiles: [WorkingTreeFile](),
                    uncommittedFiles: [String]()
                )
            }

            let status = self.workingTreeParser.parsePorcelainStatus(statusResult.output)
            let stagedDiffs = self.workingTreeParser.parseNumstat(
                self.executeGitCommand(in: repositoryPath, args: ["diff", "--cached", "--numstat", "--no-renames"]).output
            )
            var changedDiffs = self.workingTreeParser.parseNumstat(
                self.executeGitCommand(in: repositoryPath, args: ["diff", "--numstat", "--no-renames"]).output
            )
            let untrackedDiffs = self.workingTreeParser.lineDiffForUntrackedFiles(
                paths: status.untrackedPaths,
                repositoryPath: repositoryPath
            )
            for (path, diff) in untrackedDiffs {
                changedDiffs[path] = diff
            }

            let stagedEntries = status.stagedStatuses.keys
                .sorted()
                .map { path in
                    WorkingTreeFile(
                        path: path,
                        lineDiff: stagedDiffs[path] ?? .zero,
                        status: status.stagedStatuses[path] ?? .modified
                    )
                }
            let changedEntries = status.changedStatuses.keys
                .sorted()
                .map { path in
                    WorkingTreeFile(
                        path: path,
                        lineDiff: changedDiffs[path] ?? .zero,
                        status: status.changedStatuses[path] ?? .modified
                    )
                }
            let merged = Array(Set(status.stagedStatuses.keys).union(status.changedStatuses.keys)).sorted()

            return (
                stagedFiles: stagedEntries,
                changedFiles: changedEntries,
                uncommittedFiles: merged
            )
        }

        await publishOnMainActor {
            self.stagedFiles = snapshot.stagedFiles
            self.changedFiles = snapshot.changedFiles
            self.uncommittedFiles = snapshot.uncommittedFiles
        }
    }

    func stageFile(path: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            completion?(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["add", "--", path])
            if result.failure {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to stage '\(path)': \(result.output)"])))
                }
                return
            }

            DispatchQueue.main.async {
                self.updateUncommittedFiles {
                    completion?(.success(()))
                }
            }
        }
    }

    func stageAllChanges(completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            completion?(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["add", "-A"])
            if result.failure {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to stage all changes: \(result.output)"])))
                }
                return
            }

            DispatchQueue.main.async {
                self.updateUncommittedFiles {
                    completion?(.success(()))
                }
            }
        }
    }

    func stageAllChangesAsync() async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(makeMissingRepositoryError())
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["add", "-A"])
        }

        guard !result.failure else {
            return .failure(
                NSError(
                    domain: "GitManager",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to stage all changes: \(result.output)"]
                )
            )
        }

        await updateUncommittedFilesAsync()
        return .success(())
    }

    func unstageAllChanges(completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            completion?(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var result = self.executeGitCommand(in: self.storedRepoPath, args: ["restore", "--staged", "--", "."])
            if result.failure {
                // Fallback for environments where restore is unavailable.
                result = self.executeGitCommand(in: self.storedRepoPath, args: ["reset", "HEAD", "--", "."])
            }

            if result.failure {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to unstage all changes: \(result.output)"])))
                }
                return
            }

            DispatchQueue.main.async {
                self.updateUncommittedFiles {
                    completion?(.success(()))
                }
            }
        }
    }

    func unstageFile(path: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            completion?(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var result = self.executeGitCommand(in: self.storedRepoPath, args: ["restore", "--staged", "--", path])
            if result.failure {
                // Fallback for environments where restore is unavailable.
                result = self.executeGitCommand(in: self.storedRepoPath, args: ["reset", "HEAD", "--", path])
            }

            if result.failure {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to unstage '\(path)': \(result.output)"])))
                }
                return
            }

            DispatchQueue.main.async {
                self.updateUncommittedFiles {
                    completion?(.success(()))
                }
            }
        }
    }

    // MARK: - File Operations

    func openFile(path: String) {
        let fullPath = (storedRepoPath as NSString).appendingPathComponent(path)
        NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
    }

    func revealInFinder(path: String) {
        let fullPath = (storedRepoPath as NSString).appendingPathComponent(path)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fullPath)])
    }

    func discardFileChanges(path: String, status: WorkingTreeFileStatus, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            completion?(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var result: (output: String, failure: Bool)
            let fullPath = (self.storedRepoPath as NSString).appendingPathComponent(path)

            if status == .untracked {
                // Untracked file: just remove it
                do {
                    if FileManager.default.fileExists(atPath: fullPath) {
                        try FileManager.default.removeItem(atPath: fullPath)
                    }
                    result = ("", false)
                } catch {
                    result = (error.localizedDescription, true)
                }
            } else {
                // If it's staged, we should unstage it and then discard it
                // Using git checkout -- path or git restore --staged --worktree
                result = self.executeGitCommand(in: self.storedRepoPath, args: ["restore", "--staged", "--worktree", "--", path])
                if result.failure {
                    // Fallback
                    _ = self.executeGitCommand(in: self.storedRepoPath, args: ["reset", "HEAD", "--", path])
                    result = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "--", path])

                    // If it was a newly added file but already tracked in index (A), check if we need to remove it
                    if FileManager.default.fileExists(atPath: fullPath) {
                        let lsResult = self.executeGitCommand(in: self.storedRepoPath, args: ["ls-files", "--error-unmatch", path])
                        if lsResult.failure {
                            try? FileManager.default.removeItem(atPath: fullPath)
                            result = ("", false)
                        }
                    }
                }
            }

            if result.failure {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to discard '\(path)': \(result.output)"])))
                }
                return
            }

            DispatchQueue.main.async {
                self.updateUncommittedFiles {
                    completion?(.success(()))
                }
            }
        }
    }

    func discardAllUnstagedChanges(completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            completion?(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Restore tracked files
            var result = self.executeGitCommand(in: self.storedRepoPath, args: ["restore", "--", "."])
            if result.failure {
                result = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "--", "."])
            }

            // Clean untracked files
            let cleanResult = self.executeGitCommand(in: self.storedRepoPath, args: ["clean", "-fd"])

            if result.failure || cleanResult.failure {
                let errorMsg = result.failure ? result.output : cleanResult.output
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to discard untracked changes: \(errorMsg)"])))
                }
                return
            }

            DispatchQueue.main.async {
                self.updateUncommittedFiles {
                    completion?(.success(()))
                }
            }
        }
    }

    func discardAllStagedChanges(completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            completion?(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // First get all staged files
            let diffResult = self.executeGitCommand(in: self.storedRepoPath, args: ["diff", "--cached", "--name-only"])
            if diffResult.failure {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get staged files: \(diffResult.output)"])))
                }
                return
            }

            let files = diffResult.output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

            guard !files.isEmpty else {
                DispatchQueue.main.async {
                    completion?(.success(()))
                }
                return
            }

            // Restore those files from index and worktree
            var result = self.executeGitCommand(in: self.storedRepoPath, args: ["restore", "--staged", "--worktree", "--"] + files)
            if result.failure {
                _ = self.executeGitCommand(in: self.storedRepoPath, args: ["reset", "HEAD", "--"] + files)
                result = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "--"] + files)

                // For files that were 'Added' but didn't exist in HEAD, 'checkout' will fail or just complain. We should carefully delete them.
                for file in files {
                    let fullPath = (self.storedRepoPath as NSString).appendingPathComponent(file)
                    let lsResult = self.executeGitCommand(in: self.storedRepoPath, args: ["ls-files", "--error-unmatch", file])
                    if lsResult.failure, FileManager.default.fileExists(atPath: fullPath) {
                        try? FileManager.default.removeItem(atPath: fullPath)
                    }
                }
            }

            DispatchQueue.main.async {
                self.updateUncommittedFiles {
                    completion?(.success(()))
                }
            }
        }
    }

    func diffStaged() -> String {
        guard !storedRepoPath.isEmpty else {
            return ""
        }

        let result = executeGitCommand(in: storedRepoPath, args: ["diff", "--cached", "--", "."])
        if result.failure {
            return ""
        }
        return result.output
    }

    func diffUnstaged() -> String {
        guard !storedRepoPath.isEmpty else {
            return ""
        }

        let trackedResult = executeGitCommand(in: storedRepoPath, args: ["diff", "--", "."])
        let trackedDiff = trackedResult.failure ? "" : trackedResult.output
        let untrackedDiff = diffForUntrackedFiles()
        return [trackedDiff, untrackedDiff]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    func diffAll() -> String {
        let stagedDiff = diffStaged()
        let unstagedDiff = diffUnstaged()
        return [stagedDiff, unstagedDiff]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    func hasUncommittedChanges() -> Bool {
        guard !storedRepoPath.isEmpty else {
            return false
        }

        return !executeGitCommand(in: storedRepoPath, args: ["status", "--porcelain"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func hasUncommittedChangesAsync() async -> Bool {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return false
        }

        return await runOnBackground {
            !self.executeGitCommand(in: repositoryPath, args: ["status", "--porcelain"])
                .output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    func isMergeCommit(_ hash: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        commitHistoryService.isMergeCommit(hash, completion: completion)
    }

    func isCommitPublishedToUpstream(_ hash: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        commitHistoryService.isCommitPublishedToUpstream(hash, completion: completion)
    }

    func isCommitPublishedToUpstreamAsync(_ hash: String) async throws -> Bool {
        try await commitHistoryService.isCommitPublishedToUpstreamAsync(hash)
    }

    func diffForCommit(_ hash: String, completion: @escaping (Result<String, Error>) -> Void) {
        commitHistoryService.diffForCommit(hash, completion: completion)
    }

    func diffForCommitAsync(_ hash: String) async throws -> String {
        try await commitHistoryService.diffForCommitAsync(hash)
    }

    func rewriteCommitMessage(
        commitHash: String,
        newMessage: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await rewriteCommitMessageAsync(commitHash: commitHash, newMessage: newMessage)
                await publishOnMainActor {
                    completion(.success(()))
                }
            } catch {
                await publishOnMainActor {
                    completion(.failure(error))
                }
            }
        }
    }

    func rewriteCommitMessageAsync(commitHash: String, newMessage: String) async throws {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            throw makeMissingRepositoryError()
        }

        if await hasUncommittedChangesAsync() {
            throw NSError(
                domain: "GitManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Commit message editing requires a clean working tree."]
            )
        }

        let mergeStatus = await commitHistoryService.checkIsMergeCommitAsync(commitHash)
        switch mergeStatus {
        case let .failure(error):
            throw error
        case let .success(isMergeCommit) where isMergeCommit:
            throw NSError(
                domain: "GitManager",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Editing merge commits is not supported yet."]
            )
        case .success:
            break
        }

        let rewriteResult: Result<Void, Error> = await runOnBackground {
            let headResult = self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "HEAD"])
            guard !headResult.failure else {
                return .failure(
                    NSError(
                        domain: "GitManager",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to resolve HEAD: \(headResult.output)"]
                    )
                )
            }

            let headHash = headResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if commitHash == headHash {
                return self.amendHeadCommitMessage(newMessage)
            }

            return self.rewordHistoricalCommitMessage(commitHash: commitHash, newMessage: newMessage)
        }

        switch rewriteResult {
        case let .failure(error):
            throw error
        case .success:
            await refreshAsync(includeReflogHistory: false)
        }
    }

    private func diffForUntrackedFiles() -> String {
        let untrackedResult = executeGitCommand(in: storedRepoPath, args: ["ls-files", "--others", "--exclude-standard"])
        if untrackedResult.failure {
            return ""
        }

        let files = untrackedResult.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if files.isEmpty {
            return ""
        }

        let sections = files.map { file -> String in
            let diffResult = executeGitCommand(in: storedRepoPath, args: ["diff", "--no-index", "--", "/dev/null", file])
            let output = diffResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return "diff --git a/\(file) b/\(file)\nnew file mode 100644\n+<unable to render diff>"
            }
            return output
        }

        return sections.joined(separator: "\n\n")
    }

    func updateBranchInfo(completion: (() -> Void)? = nil) {
        branchService.updateBranchInfo(completion: completion)
    }

    func updateBranchInfoAsync() async {
        await branchService.updateBranchInfoAsync()
    }

    func resetToLastCommit() {
        guard !storedRepoPath.isEmpty else {
            print("Error: No repository path configured")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Reset to last commit (discard all changes)
            let resetResult = self.executeGitCommand(in: self.storedRepoPath, args: ["reset", "--hard", "HEAD"])

            if resetResult.failure {
                print("Error resetting to last commit: \(resetResult.output)")
                return
            }

            // Update status
            self.updateLocalCommitCount()
            self.updateUncommittedFiles()
            self.updateBranchInfo()
            print("Reset to last commit")
        }
    }

    private func amendHeadCommitMessage(_ newMessage: String) -> Result<Void, Error> {
        let result = executeGitCommand(
            in: storedRepoPath,
            args: [
                "commit",
                "--amend",
                "--no-gpg-sign",
                "--allow-empty-message",
                "--cleanup=verbatim",
                "-m",
                newMessage
            ]
        )

        if result.failure {
            return .failure(NSError(domain: "GitManager", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to amend commit message: \(result.output)"]))
        }

        return .success(())
    }

    private func rewordHistoricalCommitMessage(commitHash: String, newMessage: String) -> Result<Void, Error> {
        let parentResult = executeGitCommand(in: storedRepoPath, args: ["rev-parse", "\(commitHash)^"])
        let isRootCommit = parentResult.failure
        let parentReference = parentResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sequenceEditorPath = writeTemporaryScript(contents: sequenceEditorScript(), executable: true),
              let messageEditorPath = writeTemporaryScript(contents: messageEditorScript(), executable: true),
              let messageFilePath = writeTemporaryScript(contents: newMessage, executable: false)
        else {
            return .failure(NSError(domain: "GitManager", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare commit rewrite scripts."]))
        }

        defer {
            cleanupTemporaryArtifacts([sequenceEditorPath, messageEditorPath, messageFilePath])
        }

        let additionalEnvironment = [
            "GIT_SEQUENCE_EDITOR": sequenceEditorPath,
            "GIT_EDITOR": messageEditorPath,
            "TARGET_COMMIT_HASH": commitHash,
            "COMMIT_MESSAGE_FILE": messageFilePath
        ]

        let args = isRootCommit ? ["rebase", "-i", "--root"] : ["rebase", "-i", parentReference]
        let rebaseResult = executeGitCommand(
            in: storedRepoPath,
            args: args,
            additionalEnvironment: additionalEnvironment
        )

        if rebaseResult.failure {
            _ = executeGitCommand(in: storedRepoPath, args: ["rebase", "--abort"])
            return .failure(NSError(domain: "GitManager", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to rewrite commit message: \(rebaseResult.output)"]))
        }

        return .success(())
    }

    private func sequenceEditorScript() -> String {
        """
        #!/bin/sh
        todo_file="$1"
        temp_file="${todo_file}.tmp"
        target="$TARGET_COMMIT_HASH"

        awk -v target="$target" '
        BEGIN { updated = 0 }
        {
            if (!updated && $1 == "pick" && index(target, $2) == 1) {
                $1 = "reword"
                updated = 1
            }
            print
        }
        END {
            if (!updated) {
                exit 2
            }
        }
        ' "$todo_file" > "$temp_file" && mv "$temp_file" "$todo_file"
        """
    }

    private func messageEditorScript() -> String {
        """
        #!/bin/sh
        cat "$COMMIT_MESSAGE_FILE" > "$1"
        """
    }

    private func writeTemporaryScript(contents: String, executable: Bool) -> String? {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitmenubar-\(UUID().uuidString)")
            .path

        do {
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            let permissions = executable ? 0o700 : 0o600
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
            return path
        } catch {
            print("Failed to write temporary file: \(error.localizedDescription)")
            return nil
        }
    }

    private func cleanupTemporaryArtifacts(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func fetchCommitHistory(limit: Int? = nil, includeReflog: Bool? = nil) {
        commitHistoryService.fetchCommitHistory(limit: limit, includeReflog: includeReflog)
    }

    func fetchCommitHistoryAsync(limit: Int? = nil, includeReflog: Bool? = nil) async {
        await commitHistoryService.fetchCommitHistoryAsync(limit: limit, includeReflog: includeReflog)
    }

    func loadMoreCommitHistory(batchSize: Int = 25) {
        commitHistoryService.loadMoreCommitHistory(batchSize: batchSize)
    }

    func resetToCommit(_ hash: String) {
        guard !storedRepoPath.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            // Do a hard reset to the specified commit while staying on the current branch
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["reset", "--hard", hash])

            if result.failure {
                print("Error resetting to commit: \(result.output)")
            } else {
                DispatchQueue.main.async {
                    self.refresh(includeReflogHistory: true)
                    print("Reset to commit: \(hash)")
                }
            }
        }
    }

    /// Wipes the repository history, leaving only a single "Initial commit" with current files
    /// Uses the orphan branch approach to completely remove all history
    func wipeRepository(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(makeRepositoryWipeNSError(code: 1, description: "No repository path configured")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.ensureBackupIgnorePatternForRepositoryWipe()
                let backupPath = try self.backupGitDirectoryForRepositoryWipe()
                print("Backed up .git folder to: \(backupPath)")

                let branchToWipe = try self.detectBranchToWipe()
                try self.createOrphanBranchForRepositoryWipe()
                try self.stageFilesForRepositoryWipe()
                try self.createInitialCommitForRepositoryWipe()
                try self.replaceBranchHistory(branchToWipe: branchToWipe)

                _ = self.executeGitCommand(in: self.storedRepoPath, args: ["gc", "--prune=now"])
                DispatchQueue.main.async {
                    self.refresh()
                    completion(.success(()))
                }
            } catch let error as RepositoryWipeError {
                self.reportRepositoryWipeFailure(error, completion: completion)
            } catch {
                self.reportRepositoryWipeFailure(
                    RepositoryWipeError(code: 0, description: error.localizedDescription),
                    completion: completion
                )
            }
        }
    }

    private func makeRepositoryWipeNSError(code: Int, description: String) -> NSError {
        NSError(domain: "GitManager", code: code, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func reportRepositoryWipeFailure(
        _ error: RepositoryWipeError,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(.failure(self.makeRepositoryWipeNSError(code: error.code, description: error.description)))
        }
    }

    private func ensureBackupIgnorePatternForRepositoryWipe() {
        let gitignorePath = (storedRepoPath as NSString).appendingPathComponent(".gitignore")
        let backupIgnorePattern = ".git-backup-*"

        do {
            var gitignoreContent = ""
            if FileManager.default.fileExists(atPath: gitignorePath) {
                gitignoreContent = try String(contentsOfFile: gitignorePath, encoding: .utf8)
            }

            guard !gitignoreContent.contains(backupIgnorePattern) else {
                return
            }

            if !gitignoreContent.isEmpty, !gitignoreContent.hasSuffix("\n") {
                gitignoreContent += "\n"
            }
            gitignoreContent += backupIgnorePattern + "\n"
            try gitignoreContent.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
            print("Added \(backupIgnorePattern) to .gitignore")
        } catch {
            print("Warning: Could not update .gitignore: \(error.localizedDescription)")
        }
    }

    private func backupGitDirectoryForRepositoryWipe() throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupPath = ".git-backup-\(timestamp)"

        let backupResult = executeCommand(in: storedRepoPath, executable: "/bin/cp", args: ["-R", ".git", backupPath])
        guard !backupResult.failure else {
            throw RepositoryWipeError(
                code: 0,
                description: "Failed to backup .git folder: \(backupResult.output)"
            )
        }

        return backupPath
    }

    private func detectBranchToWipe() throws -> String {
        let branchParseResult = executeGitCommand(in: storedRepoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
        guard !branchParseResult.failure else {
            throw RepositoryWipeError(
                code: 2,
                description: "Failed to detect current branch: \(branchParseResult.output)"
            )
        }

        let branchToWipe = branchParseResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard branchToWipe != "HEAD" else {
            throw RepositoryWipeError(
                code: 2,
                description: "Cannot wipe in detached HEAD state. Please checkout a branch first."
            )
        }

        return branchToWipe
    }

    private func createOrphanBranchForRepositoryWipe() throws {
        let orphanResult = executeGitCommand(in: storedRepoPath, args: ["checkout", "--orphan", "temp_wipe_branch"])
        guard !orphanResult.failure else {
            throw RepositoryWipeError(
                code: 2,
                description: "Failed to create orphan branch: \(orphanResult.output)"
            )
        }
    }

    private func stageFilesForRepositoryWipe() throws {
        let addResult = executeGitCommand(in: storedRepoPath, args: ["add", "-A"])
        guard !addResult.failure else {
            throw RepositoryWipeError(code: 3, description: "Failed to stage files: \(addResult.output)")
        }
    }

    private func createInitialCommitForRepositoryWipe() throws {
        let commitResult = executeGitCommand(
            in: storedRepoPath,
            args: ["commit", "--no-gpg-sign", "-m", "Initial commit"]
        )
        guard !commitResult.failure else {
            throw RepositoryWipeError(
                code: 4,
                description: "Failed to create initial commit: \(commitResult.output)"
            )
        }
    }

    private func replaceBranchHistory(branchToWipe: String) throws {
        let deleteBranchResult = executeGitCommand(in: storedRepoPath, args: ["branch", "-D", branchToWipe])
        if deleteBranchResult.failure {
            print("Warning: Could not delete old branch \(branchToWipe): \(deleteBranchResult.output)")
        }

        let renameResult = executeGitCommand(in: storedRepoPath, args: ["branch", "-m", branchToWipe])
        guard !renameResult.failure else {
            throw RepositoryWipeError(
                code: 5,
                description: "Failed to rename branch to \(branchToWipe): \(renameResult.output)"
            )
        }

        let forcePushResult = executeGitCommand(
            in: storedRepoPath,
            args: ["push", "-u", "-f", "origin", branchToWipe],
            useAuth: true
        )
        guard !forcePushResult.failure else {
            throw RepositoryWipeError(
                code: 6,
                description: "Failed to force push to \(branchToWipe): \(forcePushResult.output)"
            )
        }
    }

    private func executeGitCommand(
        in directory: String,
        args: [String],
        useAuth: Bool = false,
        additionalEnvironment: [String: String] = [:]
    ) -> (output: String, failure: Bool) {
        GitExecution.executeGitCommand(
            in: directory,
            args: args,
            useAuth: useAuth,
            additionalEnvironment: additionalEnvironment,
            using: commandRunner
        )
    }

    private func executeCommand(
        in directory: String,
        executable: String,
        args: [String],
        useAuth: Bool = false,
        additionalEnvironment: [String: String] = [:]
    ) -> (output: String, failure: Bool) {
        commandRunner.runCommand(
            in: directory,
            executable: executable,
            args: args,
            useAuth: useAuth,
            additionalEnvironment: additionalEnvironment
        )
    }

    // MARK: - Branch Management

    func fetchBranches(completion: (() -> Void)? = nil) {
        branchService.fetchBranches(completion: completion)
    }

    func fetchBranchesAsync() async {
        await branchService.fetchBranchesAsync()
    }

    // MARK: - Branch Management (Local/Remote separation)

    func fetchLocalBranchesAsync() async -> [String] {
        await branchService.fetchLocalBranchesAsync()
    }

    func fetchRemoteBranchesAsync() async -> [String] {
        await branchService.fetchRemoteBranchesAsync()
    }

    func pushBranchToRemoteAsync(branchName: String) async -> Result<Void, Error> {
        await branchService.pushBranchToRemoteAsync(branchName: branchName)
    }

    func deleteRemoteBranchAsync(branchName: String) async -> Result<Void, Error> {
        await branchService.deleteRemoteBranchAsync(branchName: branchName)
    }

    func getDefaultBranchNameAsync() async -> String {
        await branchService.getDefaultBranchNameAsync()
    }

    func resolveBranchInfoAsync() async -> [BranchInfo] {
        await branchService.resolveBranchInfoAsync()
    }

    func resolveWorktreeSnapshotAsync() async -> Result<GitWorktreeSnapshot, Error> {
        await branchService.resolveWorktreeSnapshotAsync()
    }

    func performCleanupAsync(
        targets: [GitCleanupTarget],
        snapshot: GitWorktreeSnapshot
    ) async -> Result<GitCleanupBatchResult, Error> {
        await branchService.performCleanupAsync(targets: targets, snapshot: snapshot)
    }

    /// Merges `featureBranch` into the default branch without deleting anything.
    /// The implementation lives in `GitBranchService`; this facade delegates to it.
    ///
    /// The caller is responsible for presenting any pre-merge confirmation; this
    /// method performs the work and refreshes state on success. Cleanup is a
    /// separate step via ``cleanupMergedBranchAsync(featureBranch:cleanupOption:)``.
    func mergeFeatureIntoDefaultAsync(
        featureBranch: String
    ) async -> Result<MergeToDefaultResult, Error> {
        await branchService.mergeFeatureIntoDefaultAsync(featureBranch: featureBranch)
    }

    /// Deletes an already-merged feature branch locally and/or remotely. The
    /// implementation lives in `GitBranchService`; this facade delegates to it.
    func cleanupMergedBranchAsync(
        featureBranch: String,
        cleanupOption: BranchCleanupOption
    ) async -> Result<MergeToDefaultResult, Error> {
        await branchService.cleanupMergedBranchAsync(
            featureBranch: featureBranch,
            cleanupOption: cleanupOption
        )
    }

    func checkRemoteStatus(completion: (() -> Void)? = nil) {
        branchService.checkRemoteStatus(completion: completion)
    }

    func checkRemoteStatusAsync() async {
        await branchService.checkRemoteStatusAsync()
    }

    func checkRepoVisibility(completion: (() -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            await checkRepoVisibilityAsync()
            await publishOnMainActor {
                completion?()
            }
        }
    }

    func checkRepoVisibilityAsync() async {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
                self.isPrivate = false
            }
            return
        }

        let remoteURL = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["config", "--get", "remote.origin.url"])
                .output
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let reference = GitHubRemoteURLParser.parse(remoteURL), let apiClient = githubAPIClient else {
            return
        }

        do {
            let repository = try await apiClient.getRepository(
                owner: reference.owner,
                name: reference.repository
            )
            await publishOnMainActor {
                self.isPrivate = repository.private
            }
        } catch {
            print("Error checking repo visibility: \(error)")
        }
    }

    func pullFromRemote(rebase: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        Task { [weak self] in
            guard let self else { return }
            let result = await pullFromRemoteAsync(rebase: rebase)
            await publishOnMainActor {
                completion(result)
            }
        }
    }

    func pullFromRemoteAsync(rebase: Bool) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(makeMissingRepositoryError())
        }

        return await runOnBackground {
            let args = rebase ? ["pull", "--rebase"] : ["pull"]
            let result = self.executeGitCommand(in: repositoryPath, args: args, useAuth: true)

            guard !result.failure else {
                if result.output.contains("CONFLICT") || result.output.contains("conflict") {
                    return .failure(
                        NSError(
                            domain: "GitManager",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Merge conflict - please resolve manually"]
                        )
                    )
                }

                return .failure(
                    NSError(
                        domain: "GitManager",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Pull failed: \(result.output)"]
                    )
                )
            }

            print("Successfully pulled from remote")
            return .success(())
        }
    }

    func pullToNewBranch(newBranchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Create a new branch originating from the upstream branch of our current branch
            // git checkout -b <newBranchName> @{u}
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "-b", newBranchName, "@{u}"])

            if result.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create branch from remote: \(result.output)"])))
                }
            } else {
                print("Successfully created branch \(newBranchName) from remote")
                DispatchQueue.main.async {
                    self.refresh {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func createBranchFromCurrentHead(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        branchService.createBranchFromCurrentHead(branchName: branchName, completion: completion)
    }

    func switchBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        branchService.switchBranch(branchName: branchName, completion: completion)
    }

    func createBranch(branchName: String, fromBranch: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        branchService.createBranch(branchName: branchName, fromBranch: fromBranch, completion: completion)
    }

    func mergeBranch(fromBranch: String, completion: @escaping (Result<Void, Error>) -> Void) {
        branchService.mergeBranch(fromBranch: fromBranch, completion: completion)
    }

    func deleteBranch(branchName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        branchService.deleteBranch(branchName: branchName, completion: completion)
    }

    func renameBranch(oldName: String, newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        branchService.renameBranch(oldName: oldName, newName: newName, completion: completion)
    }
}

// swiftlint:enable type_body_length file_length
