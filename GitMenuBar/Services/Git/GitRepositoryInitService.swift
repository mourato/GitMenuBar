import Foundation

/// Owns repository creation and remote setup for an explicit repository path.
@MainActor
final class GitRepositoryInitService {
    var githubAPIClient: GitHubAPIClient?
    private let commandRunner: GitCommandRunner

    init(commandRunner: GitCommandRunner) {
        self.commandRunner = commandRunner
    }

    private func runOnBackground<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    private nonisolated func executeGitCommand(
        in directory: String,
        args: [String],
        useAuth: Bool = false
    ) -> (output: String, failure: Bool) {
        GitExecution.executeGitCommand(in: directory, args: args, useAuth: useAuth, using: commandRunner)
    }

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
        Task { @MainActor in
            // First check if remote is configured.
            let remoteConfigResult = await runOnBackground {
                self.executeGitCommand(in: path, args: ["config", "--get", "remote.origin.url"])
            }
            guard !remoteConfigResult.failure else {
                completion(false)
                return
            }

            let remoteURL = remoteConfigResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remoteURL.isEmpty else {
                completion(false)
                return
            }

            // Parse owner and repo from URL.
            // Supports formats like:
            // - https://github.com/owner/repo
            // - https://github.com/owner/repo.git
            // - git@github.com:owner/repo.git
            guard let reference = GitHubRemoteURLParser.parse(remoteURL) else {
                completion(true)
                return
            }

            // Check if repo exists using GitHub API.
            guard let apiClient = self.githubAPIClient else {
                completion(true)
                return
            }

            let exists = await apiClient.checkRepositoryURLExists(
                owner: reference.owner,
                repo: reference.repository
            )
            completion(exists)
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
}
