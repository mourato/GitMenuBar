//
//  GitManager.swift
//  GitMenuBar
//

import AppKit
import Foundation

// swiftlint:disable type_body_length file_length
class GitManager: ObservableObject {
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

    init(repositoryPathOverride: String? = nil) {
        repositoryContext = GitRepositoryContext(overridePath: repositoryPathOverride)
        commandRunner = GitCommandRunner()
        workingTreeParser = WorkingTreeParser(runner: commandRunner)
        updateLocalCommitCount()
        updateUncommittedFiles()
        updateBranchInfo()
        updateRemoteUrl()
        fetchCommitHistory()
        fetchBranches()
    }

    private var storedRepoPath: String {
        get { repositoryContext.repositoryPath }
        set { repositoryContext.repositoryPath = newValue }
    }

    func refresh(completion: (() -> Void)? = nil) {
        updateLocalCommitCount()
        updateUncommittedFiles {
            self.updateBranchInfo {
                self.updateRemoteUrl()
                self.fetchCommitHistory()
                self.fetchBranches()
                self.checkRemoteStatus()
                self.checkRepoVisibility()
                completion?()
            }
        }
    }

    func commitLocally(_ message: String, skipUIUpdates: Bool = false, completion: (() -> Void)? = nil) {
        isCommitting = true
        guard !storedRepoPath.isEmpty else {
            print("Error: No repository path configured in settings")
            isCommitting = false
            completion?()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Commit only what is already staged.
            let commitResult = self.executeGitCommand(in: self.storedRepoPath, args: ["commit", "--no-gpg-sign", "-m", message])
            if commitResult.failure {
                print("Error creating commit: \(commitResult.output)")
                DispatchQueue.main.async {
                    self.isCommitting = false
                    completion?()
                }
                return
            }

            DispatchQueue.main.async {
                self.isCommitting = false
                // Only update UI if we're not about to close the popover
                if !skipUIUpdates {
                    self.updateLocalCommitCount()
                    self.updateUncommittedFiles()
                    self.updateBranchInfo()
                }
                print("Created local commit: \(message)")
                completion?()
            }
        }
    }

    func commitLocallyWithFallback(_ message: String, skipUIUpdates: Bool = false, completion: (() -> Void)? = nil) {
        updateUncommittedFiles {
            let shouldAutoStage = self.stagedFiles.isEmpty && !self.changedFiles.isEmpty

            guard shouldAutoStage else {
                self.commitLocally(message, skipUIUpdates: skipUIUpdates, completion: completion)
                return
            }

            self.stageAllChanges { result in
                switch result {
                case .success:
                    self.commitLocally(message, skipUIUpdates: skipUIUpdates, completion: completion)
                case let .failure(error):
                    print("Error staging all changes for fallback commit: \(error.localizedDescription)")
                    completion?()
                }
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
        // First check if remote is configured
        guard hasRemoteConfigured(at: path) else {
            completion(false)
            return
        }

        // Get the remote URL
        let result = executeGitCommand(in: path, args: ["config", "--get", "remote.origin.url"])
        guard !result.failure else {
            completion(false)
            return
        }

        let remoteURL = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse owner and repo from URL
        // Supports formats like:
        // - https://github.com/owner/repo
        // - https://github.com/owner/repo.git
        // - git@github.com:owner/repo.git

        guard let reference = GitHubRemoteURLParser.parse(remoteURL) else {
            // Not a GitHub URL, assume it exists
            completion(true)
            return
        }

        // Check if repo exists using GitHub API
        guard let apiClient = githubAPIClient else {
            // No API client available, assume exists
            completion(true)
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
        // Use current branch as target
        pushToBranch(branchName: currentBranch, force: false, completion: completion)
    }

    func pushToBranch(branchName: String, force: Bool, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            let error = NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error: No repository path configured"])
            print(error.localizedDescription)
            DispatchQueue.main.async {
                completion?(.failure(error))
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Determine push arguments
            var pushArgs: [String]

            if branchName == self.currentBranch {
                // Pushing current branch - always use -u to set/update upstream
                pushArgs = force ? ["push", "--force", "-u", "origin", branchName] : ["push", "-u", "origin", branchName]
            } else {
                // Pushing current HEAD to a different remote branch
                pushArgs = force ? ["push", "--force", "origin", "HEAD:\(branchName)"] : ["push", "origin", "HEAD:\(branchName)"]
            }

            let pushResult = self.executeGitCommand(in: self.storedRepoPath, args: pushArgs, useAuth: true)

            // If normal push fails, check if it's because of diverged history
            if pushResult.failure {
                // Check if the error is about diverged branches (common after reset)
                if pushResult.output.contains("rejected") || pushResult.output.contains("diverged") || pushResult.output.contains("non-fast-forward") {
                    print("History has diverged, attempting force push...")

                    // Do a force push to overwrite remote history
                    let forcePushArgs = branchName == self.currentBranch ? ["push", "--force", "-u", "origin", branchName] : ["push", "--force", "origin", "HEAD:\(branchName)"]
                    let forcePushResult = self.executeGitCommand(in: self.storedRepoPath, args: forcePushArgs, useAuth: true)

                    if forcePushResult.failure {
                        let error = NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error force pushing: \(forcePushResult.output)"])
                        print(error.localizedDescription)
                        DispatchQueue.main.async {
                            completion?(.failure(error))
                        }
                        return
                    }

                    print("Successfully force pushed commits to remote")
                } else {
                    let error = NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Error pushing: \(pushResult.output)"])
                    print(error.localizedDescription)
                    DispatchQueue.main.async {
                        completion?(.failure(error))
                    }
                    return
                }
            } else {
                print("Successfully pushed commits to remote")
            }

            // Success
            DispatchQueue.main.async {
                completion?(.success(()))
            }
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
                    let revListMaster = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/master"])
                    let count = Int(revListMaster.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

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
                    let revListMaster = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--count", "HEAD", "^origin/master"])
                    if !revListMaster.failure, let count = Int(revListMaster.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        isAhead = count > 0
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

    func fetchCommitHistory() {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.commitHistory = []
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Get all commits including "future" ones from reflog
            // This shows commits even if we've reset backwards
            // Use Unix timestamp (%at) for unambiguous time parsing
            let args = ["log", "--all", "--reflog", "--pretty=format:%H|%s|%at|%an", "-n", "100"]

            let result = self.executeGitCommand(in: self.storedRepoPath, args: args)

            if !result.failure {
                var seenHashes = Set<String>()
                let commits = result.output.components(separatedBy: .newlines).compactMap { line -> Commit? in
                    let parts = line.components(separatedBy: "|")
                    guard parts.count >= 4 else { return nil }
                    let hash = parts[0]
                    // Skip duplicate commits (reflog can show same commit multiple times)
                    guard !seenHashes.contains(hash) else { return nil }
                    seenHashes.insert(hash)

                    // Parse timestamp
                    guard let timestamp = TimeInterval(parts[2]) else { return nil }
                    let startOfDate = Date(timeIntervalSince1970: timestamp)

                    // Format date
                    let formattedDate = self.formatCommitDate(startOfDate)

                    return Commit(id: hash, message: parts[1], date: formattedDate, author: parts[3])
                }

                DispatchQueue.main.async {
                    self.commitHistory = commits
                }
            } else {
                DispatchQueue.main.async {
                    self.commitHistory = []
                }
            }
        }
    }

    private func formatCommitDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            // Show time for today's commits - respects system 12/24h setting
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            timeFormatter.dateStyle = .none
            return timeFormatter.string(from: date)
        } else {
            // Show date for older commits - respects locale order
            let dateFormatter = DateFormatter()
            dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
            return dateFormatter.string(from: date)
        }
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
                    self.refresh()
                    print("Reset to commit: \(hash)")
                }
            }
        }
    }

    /// Wipes the repository history, leaving only a single "Initial commit" with current files
    /// Uses the orphan branch approach to completely remove all history
    func wipeRepository(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Step 0a: Ensure .git-backup-* is in .gitignore before creating backup
            let gitignorePath = (self.storedRepoPath as NSString).appendingPathComponent(".gitignore")
            let backupIgnorePattern = ".git-backup-*"

            do {
                var gitignoreContent = ""
                if FileManager.default.fileExists(atPath: gitignorePath) {
                    gitignoreContent = try String(contentsOfFile: gitignorePath, encoding: .utf8)
                }

                // Check if pattern already exists
                if !gitignoreContent.contains(backupIgnorePattern) {
                    // Add the pattern (with newline if file doesn't end with one)
                    if !gitignoreContent.isEmpty, !gitignoreContent.hasSuffix("\n") {
                        gitignoreContent += "\n"
                    }
                    gitignoreContent += backupIgnorePattern + "\n"
                    try gitignoreContent.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
                    print("Added \(backupIgnorePattern) to .gitignore")
                }
            } catch {
                print("Warning: Could not update .gitignore: \(error.localizedDescription)")
                // Continue anyway - not a fatal error
            }

            // Step 0b: Backup the .git folder before wiping
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let gitPath = ".git"
            let backupPath = ".git-backup-\(timestamp)"

            // Use shell 'cp -R' instead of FileManager.copyItem to avoid xattr permission errors on SMB
            let backupResult = self.executeCommand(in: self.storedRepoPath, executable: "/bin/cp", args: ["-R", gitPath, backupPath])
            if backupResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to backup .git folder: \(backupResult.output)"])))
                }
                return
            }
            print("Backed up .git folder to: \(backupPath)")

            // Step 1: Detect current branch to wipe
            let branchParseResult = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
            if branchParseResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to detect current branch: \(branchParseResult.output)"])))
                }
                return
            }

            let branchToWipe = branchParseResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            // Do not allow wiping in detached HEAD state
            if branchToWipe == "HEAD" {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot wipe in detached HEAD state. Please checkout a branch first."])))
                }
                return
            }

            // Step 2: Create an orphan branch (no history)
            let orphanResult = self.executeGitCommand(in: self.storedRepoPath, args: ["checkout", "--orphan", "temp_wipe_branch"])
            if orphanResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create orphan branch: \(orphanResult.output)"])))
                }
                return
            }

            // Step 3: Stage all current files
            let addResult = self.executeGitCommand(in: self.storedRepoPath, args: ["add", "-A"])
            if addResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to stage files: \(addResult.output)"])))
                }
                return
            }

            // Step 4: Create the fresh "Initial commit"
            let commitResult = self.executeGitCommand(in: self.storedRepoPath, args: ["commit", "--no-gpg-sign", "-m", "Initial commit"])
            if commitResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create initial commit: \(commitResult.output)"])))
                }
                return
            }

            // Step 5: Delete the old branch
            let deleteBranchResult = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-D", branchToWipe])
            if deleteBranchResult.failure {
                print("Warning: Could not delete old branch \(branchToWipe): \(deleteBranchResult.output)")
            }

            // Step 6: Rename current branch to the original branch name
            let renameResult = self.executeGitCommand(in: self.storedRepoPath, args: ["branch", "-m", branchToWipe])
            if renameResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to rename branch to \(branchToWipe): \(renameResult.output)"])))
                }
                return
            }

            // Step 7: Force push to remote to overwrite history (use -u to set upstream tracking)
            let forcePushResult = self.executeGitCommand(in: self.storedRepoPath, args: ["push", "-u", "-f", "origin", branchToWipe], useAuth: true)
            if forcePushResult.failure {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GitManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to force push to \(branchToWipe): \(forcePushResult.output)"])))
                }
                return
            }

            // Step 7: Clean up old objects (optional but thorough)
            _ = self.executeGitCommand(in: self.storedRepoPath, args: ["gc", "--prune=now"])

            // Success - refresh the UI
            DispatchQueue.main.async {
                self.refresh()
                completion(.success(()))
            }
        }
    }

    private func executeGitCommand(in directory: String, args: [String], useAuth: Bool = false) -> (output: String, failure: Bool) {
        commandRunner.runGitCommand(in: directory, args: args, useAuth: useAuth)
    }

    private func executeCommand(in directory: String, executable: String, args: [String], useAuth: Bool = false) -> (output: String, failure: Bool) {
        commandRunner.runCommand(in: directory, executable: executable, args: args, useAuth: useAuth)
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

    func checkRemoteStatus(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.isRemoteAhead = false
                self.isBehindRemote = false
                self.behindCount = 0
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // First, fetch to update remote refs (do this quietly)
            _ = self.executeGitCommand(in: self.storedRepoPath, args: ["fetch"], useAuth: true)

            // Check if we're ahead or behind remote
            // Format: "behind\tahead" (e.g., "2\t3" means 2 behind, 3 ahead)
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["rev-list", "--left-right", "--count", "@{u}...HEAD"])

            if !result.failure {
                let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
                if parts.count == 2 {
                    let behind = Int(parts[0]) ?? 0
                    let ahead = Int(parts[1]) ?? 0

                    DispatchQueue.main.async {
                        self.behindCount = behind
                        self.isRemoteAhead = behind > 0
                        self.isBehindRemote = behind > 0
                        completion?()
                    }
                    return
                }
            }

            // Fallback: no upstream or error
            DispatchQueue.main.async {
                self.isRemoteAhead = false
                self.isBehindRemote = false
                self.behindCount = 0
                completion?()
            }
        }
    }

    func checkRepoVisibility(completion: (() -> Void)? = nil) {
        guard !storedRepoPath.isEmpty else {
            DispatchQueue.main.async {
                self.isPrivate = false
                completion?()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Get URL from config to be sure
            let result = self.executeGitCommand(in: self.storedRepoPath, args: ["config", "--get", "remote.origin.url"])
            guard !result.failure else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }

            let remoteURL = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let reference = GitHubRemoteURLParser.parse(remoteURL) else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }

            guard let apiClient = self.githubAPIClient else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }

            Task {
                do {
                    let repository = try await apiClient.getRepository(
                        owner: reference.owner,
                        name: reference.repository
                    )
                    DispatchQueue.main.async {
                        self.isPrivate = repository.private
                        completion?()
                    }
                } catch {
                    print("Error checking repo visibility: \(error)")
                    DispatchQueue.main.async {
                        completion?()
                    }
                }
            }
        }
    }

    func pullFromRemote(rebase: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !storedRepoPath.isEmpty else {
            completion(.failure(NSError(domain: "GitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No repository path configured"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let args = rebase ? ["pull", "--rebase"] : ["pull"]
            let result = self.executeGitCommand(in: self.storedRepoPath, args: args, useAuth: true)

            if result.failure {
                // Check if it's a merge conflict
                if result.output.contains("CONFLICT") || result.output.contains("conflict") {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Merge conflict - please resolve manually"])))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GitManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Pull failed: \(result.output)"])))
                    }
                }
            } else {
                print("Successfully pulled from remote")
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            }
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
