//
//  GitManager.swift
//  GitMenuBar
//

import AppKit
import Foundation

// swiftlint:disable type_body_length file_length
class GitManager: ObservableObject {
    private static let defaultCommitHistoryLimit = 25

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
    @Published var availableBranches: [String] = []
    @Published var isRemoteAhead: Bool = false
    @Published var isBehindRemote: Bool = false
    @Published var remoteBranchName: String = ""
    @Published var behindCount: Int = 0
    @Published var isPrivate: Bool = false
    @Published private(set) var commitHistoryLimit = GitManager.defaultCommitHistoryLimit

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
    private let commitHistoryParser: CommitHistoryParser
    private let workingTreeParser: WorkingTreeParser
    private var includesReflogCommitsInHistory = false

    init(repositoryPathOverride: String? = nil) {
        repositoryContext = GitRepositoryContext(overridePath: repositoryPathOverride)
        commandRunner = GitCommandRunner()
        commitHistoryParser = CommitHistoryParser(runner: commandRunner)
        workingTreeParser = WorkingTreeParser(runner: commandRunner)
        updateLocalCommitCount()
        updateUncommittedFiles()
        updateBranchInfo()
        updateRemoteUrl()
        fetchCommitHistory(includeReflog: false)
        fetchBranches()
    }

    private var storedRepoPath: String {
        get { repositoryContext.repositoryPath }
        set { repositoryContext.repositoryPath = newValue }
    }

    private func runOnBackground<T>(_ operation: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: operation())
            }
        }
    }

    private func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await MainActor.run(body: update)
    }

    private func makeMissingRepositoryError() -> NSError {
        NSError(
            domain: "GitManager",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No repository path configured"]
        )
    }

    var canLoadMoreCommitHistory: Bool {
        !commitHistory.isEmpty && commitHistory.count >= commitHistoryLimit
    }

    func refreshAsync(includeReflogHistory: Bool? = nil) async {
        await updateLocalCommitCountAsync()
        await updateUncommittedFilesAsync()
        await updateBranchInfoAsync()
        await updateRemoteUrlAsync()
        await fetchCommitHistoryAsync(includeReflog: includeReflogHistory)
        await fetchBranchesAsync()
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
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.remoteUrl = ""
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["config", "--get", "remote.origin.url"])

            if !result.failure {
                let url = GitHubRemoteURLParser.normalizedWebURL(from: result.output)

                DispatchQueue.main.async {
                    self.remoteUrl = url
                }
            } else {
                DispatchQueue.main.async {
                    self.remoteUrl = ""
                }
            }
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
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.commitCount = 0
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Count commits that exist locally but not on remote (ahead of upstream)
            // uses @{u}..HEAD which calculates commits in HEAD not in upstream
            let revListResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "@{u}..HEAD"])

            if revListResult.failure {
                // Fallback: if no upstream configured, check against origin/main directly
                // (Previous logic, kept as fallback)
                let revListFallback = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/main"])

                if let count = Int(revListFallback.output.trimmingCharacters(in: .whitespacesAndNewlines)), !revListFallback.failure {
                    DispatchQueue.main.async {
                        self.commitCount = count
                        completion?()
                    }
                } else {
                    // Try with master
                    let revListDefaultBranchFallback = self.executeGitCommand(
                        in: self.storedRepoPath,
                        args: ["rev-list", "--count", "HEAD", "^origin/master"]
                    )
                    let count = Int(revListDefaultBranchFallback.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

                    DispatchQueue.main.async {
                        self.commitCount = count
                        completion?()
                    }
                }
            } else {
                let count = Int(revListResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                DispatchQueue.main.async {
                    self.commitCount = count
                    completion?()
                }
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
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.uncommittedFiles = []
                self.stagedFiles = []
                self.changedFiles = []
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Split working tree into index (staged) and worktree (changes).
            // Use -uall so newly created files inside untracked directories are listed per file.
            let statusResult = self.executeGitCommand(in: self.storedRepoPath, args: ["status", "--porcelain", "-uall"])

            if statusResult.failure {
                print("Error getting git status: \(statusResult.output)")
                DispatchQueue.main.async {
                    self.uncommittedFiles = []
                    self.stagedFiles = []
                    self.changedFiles = []
                    completion?()
                }
                return
            }

            let status = self.workingTreeParser.parsePorcelainStatus(statusResult.output)
            let stagedDiffs = self.workingTreeParser.parseNumstat(
                self.executeGitCommand(in: self.storedRepoPath, args: ["diff", "--cached", "--numstat", "--no-renames"]).output
            )
            var changedDiffs = self.workingTreeParser.parseNumstat(
                self.executeGitCommand(in: self.storedRepoPath, args: ["diff", "--numstat", "--no-renames"]).output
            )
            let untrackedDiffs = self.workingTreeParser.lineDiffForUntrackedFiles(
                paths: status.untrackedPaths,
                repositoryPath: self.storedRepoPath
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

            DispatchQueue.main.async {
                self.stagedFiles = stagedEntries
                self.changedFiles = changedEntries
                self.uncommittedFiles = merged
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
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.resolveMergeCommitStatus(for: hash)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func isCommitPublishedToUpstream(_ hash: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.resolveCommitPublishedStatus(for: hash)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func isCommitPublishedToUpstreamAsync(_ hash: String) async throws -> Bool {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            throw makeMissingRepositoryError()
        }

        let result = await runOnBackground {
            self.resolveCommitPublishedStatus(for: hash)
        }

        switch result {
        case let .success(isPublished):
            return isPublished
        case let .failure(error):
            throw error
        }
    }

    func diffForCommit(_ hash: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.resolveDiffForCommit(hash)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func diffForCommitAsync(_ hash: String) async throws -> String {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            throw makeMissingRepositoryError()
        }

        let result = await runOnBackground {
            self.resolveDiffForCommit(hash)
        }

        switch result {
        case let .success(diff):
            return diff
        case let .failure(error):
            throw error
        }
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

        let mergeStatus = await runOnBackground {
            self.resolveMergeCommitStatus(for: commitHash)
        }
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

    private func resolveMergeCommitStatus(for hash: String) -> Result<Bool, Error> {
        let result = executeGitCommand(in: storedRepoPath, args: ["rev-list", "--parents", "-n", "1", hash])
        guard !result.failure else {
            return .failure(NSError(domain: "GitManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to inspect commit: \(result.output)"]))
        }

        let hashes = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)

        return .success(hashes.count > 2)
    }

    private func resolveCommitPublishedStatus(for hash: String) -> Result<Bool, Error> {
        let upstreamResult = executeGitCommand(in: storedRepoPath, args: ["rev-parse", "--verify", "@{u}"])
        if upstreamResult.failure {
            return .success(false)
        }

        let containsResult = executeGitCommand(
            in: storedRepoPath,
            args: ["merge-base", "--is-ancestor", hash, "@{u}"]
        )

        return .success(!containsResult.failure)
    }

    private func resolveDiffForCommit(_ hash: String) -> Result<String, Error> {
        let result = executeGitCommand(
            in: storedRepoPath,
            args: ["show", "--format=", "--no-renames", "--no-ext-diff", hash]
        )

        guard !result.failure else {
            return .failure(NSError(domain: "GitManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to load commit diff: \(result.output)"]))
        }

        let diff = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diff.isEmpty else {
            return .failure(NSError(domain: "GitManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "No diff found for the selected commit."]))
        }

        return .success(diff)
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
        let resolvedLimit = max(1, limit ?? commitHistoryLimit)
        let resolvedIncludeReflog = includeReflog ?? includesReflogCommitsInHistory

        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.includesReflogCommitsInHistory = resolvedIncludeReflog
                self.commitHistoryLimit = resolvedLimit
                self.commitHistory = []
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let commits = self.commitHistoryParser.fetchCommitHistory(
                in: self.storedRepoPath,
                limit: resolvedLimit,
                includeReflog: resolvedIncludeReflog
            )

            DispatchQueue.main.async {
                self.includesReflogCommitsInHistory = resolvedIncludeReflog
                self.commitHistoryLimit = resolvedLimit
                self.commitHistory = commits
            }
        }
    }

    func fetchCommitHistoryAsync(limit: Int? = nil, includeReflog: Bool? = nil) async {
        let resolvedLimit = max(1, limit ?? commitHistoryLimit)
        let resolvedIncludeReflog = includeReflog ?? includesReflogCommitsInHistory
        let repositoryPath = storedRepoPath

        guard !repositoryPath.isEmpty else {
            await publishOnMainActor {
                self.includesReflogCommitsInHistory = resolvedIncludeReflog
                self.commitHistoryLimit = resolvedLimit
                self.commitHistory = []
            }
            return
        }

        let commits = await runOnBackground {
            self.commitHistoryParser.fetchCommitHistory(
                in: repositoryPath,
                limit: resolvedLimit,
                includeReflog: resolvedIncludeReflog
            )
        }

        await publishOnMainActor {
            self.includesReflogCommitsInHistory = resolvedIncludeReflog
            self.commitHistoryLimit = resolvedLimit
            self.commitHistory = commits
        }
    }

    func loadMoreCommitHistory(batchSize: Int = GitManager.defaultCommitHistoryLimit) {
        let nextLimit = commitHistoryLimit + max(1, batchSize)
        fetchCommitHistory(limit: nextLimit)
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
        commandRunner.runGitCommand(
            in: directory,
            args: args,
            useAuth: useAuth,
            additionalEnvironment: additionalEnvironment
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
                    self.refresh {
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
                self.refresh {
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
                    self.refresh {
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
                    self.refresh {
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
                    self.refresh {
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
                    self.refresh {
                        completion(.success(()))
                    }
                }
            }
        }
    }
}

// swiftlint:enable type_body_length file_length
