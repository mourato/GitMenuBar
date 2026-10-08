import Foundation

/// Owns working-tree operations for an explicit repository path; GitManager owns refresh publication.
@MainActor
final class GitWorkingTreeService {
    private let commandRunner: GitCommandRunner

    init(commandRunner: GitCommandRunner) {
        self.commandRunner = commandRunner
    }

    private func runOnBackground<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    private nonisolated func executeGitCommand(
        in directory: String,
        args: [String]
    ) -> (output: String, failure: Bool) {
        GitExecution.executeGitCommand(in: directory, args: args, using: commandRunner)
    }

    func stageFileAsync(path: String, in repositoryPath: String) async -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["add", "--", path])
        }
        guard !result.failure else {
            return .failure(GitOperationError.commandFailed("Failed to stage '\(path)': \(result.output)"))
        }
        return .success(())
    }

    func stageAllChangesAsync(in repositoryPath: String) async -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        let result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["add", "-A"])
        }

        guard !result.failure else {
            return .failure(
                GitOperationError.commandFailed("Failed to stage all changes: \(result.output)")
            )
        }

        return .success(())
    }

    func unstageAllChangesAsync(in repositoryPath: String) async -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        var result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["restore", "--staged", "--", "."])
        }
        if result.failure {
            result = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["reset", "HEAD", "--", "."])
            }
        }
        guard !result.failure else {
            return .failure(GitOperationError.commandFailed("Failed to unstage all changes: \(result.output)"))
        }
        return .success(())
    }

    func unstageFileAsync(path: String, in repositoryPath: String) async -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }

        var result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["restore", "--staged", "--", path])
        }
        if result.failure {
            result = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["reset", "HEAD", "--", path])
            }
        }
        guard !result.failure else {
            return .failure(GitOperationError.commandFailed("Failed to unstage '\(path)': \(result.output)"))
        }
        return .success(())
    }

    func discardFileChangesAsync(
        path: String,
        status: WorkingTreeFileStatus,
        in repositoryPath: String
    ) async -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else { return .failure(GitExecution.missingRepositoryError()) }
        let fullPath: String
        do {
            fullPath = try discardTarget(path: path, in: repositoryPath)
        } catch {
            return .failure(error)
        }
        var result: (output: String, failure: Bool)

        if status == .untracked {
            do {
                if FileManager.default.fileExists(atPath: fullPath) {
                    try FileManager.default.removeItem(atPath: fullPath)
                }
                result = ("", false)
            } catch {
                result = (error.localizedDescription, true)
            }
        } else {
            result = await runOnBackground {
                self.executeGitCommand(
                    in: repositoryPath,
                    args: ["restore", "--staged", "--worktree", "--", path]
                )
            }
            if result.failure {
                _ = await runOnBackground {
                    self.executeGitCommand(in: repositoryPath, args: ["reset", "HEAD", "--", path])
                }
                result = await runOnBackground {
                    self.executeGitCommand(in: repositoryPath, args: ["checkout", "--", path])
                }

                if FileManager.default.fileExists(atPath: fullPath) {
                    let lsResult = await runOnBackground {
                        self.executeGitCommand(in: repositoryPath, args: ["ls-files", "--error-unmatch", path])
                    }
                    if lsResult.failure {
                        do {
                            let target = try discardTarget(path: path, in: repositoryPath)
                            try FileManager.default.removeItem(atPath: target)
                            result = ("", false)
                        } catch {
                            result = (error.localizedDescription, true)
                        }
                    }
                }
            }
        }

        guard !result.failure else {
            return .failure(GitOperationError.commandFailed("Failed to discard '\(path)': \(result.output)"))
        }
        return .success(())
    }

    /// Resolve parents, but preserve a final symlink so discard removes the link itself.
    private func discardTarget(path: String, in repositoryPath: String) throws -> String {
        guard !path.isEmpty, !(path as NSString).isAbsolutePath,
              !(path as NSString).pathComponents.contains("..")
        else {
            throw GitOperationError.invalidInput("Discard requires a repository-relative file path.")
        }
        let root = URL(fileURLWithPath: repositoryPath).standardizedFileURL.resolvingSymlinksInPath()
        let target = root.appendingPathComponent(path).standardizedFileURL
        let parent = target.deletingLastPathComponent().resolvingSymlinksInPath()
        let resolved = parent.appendingPathComponent(target.lastPathComponent).standardizedFileURL
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw GitOperationError.invalidInput("Discard path must stay inside the repository.")
        }
        return resolved.path
    }

    func discardAllUnstagedChangesAsync(in repositoryPath: String) async -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else { return .failure(GitOperationError.noRepository) }
        // Restore tracked files
        var result = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["restore", "--", "."])
        }
        if result.failure {
            result = await runOnBackground {
                self.executeGitCommand(in: repositoryPath, args: ["checkout", "--", "."])
            }
        }

        // Clean untracked files
        let cleanResult = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["clean", "-fd"])
        }

        if result.failure || cleanResult.failure {
            let errorMsg = result.failure ? result.output : cleanResult.output
            return .failure(GitOperationError.commandFailed("Failed to discard untracked changes: \(errorMsg)"))
        }

        return .success(())
    }

    func diffStaged(in repositoryPath: String) -> String {
        guard !repositoryPath.isEmpty else {
            return ""
        }

        let result = executeGitCommand(in: repositoryPath, args: ["diff", "--cached", "--", "."])
        if result.failure {
            return ""
        }
        return result.output
    }

    func diffUnstaged(in repositoryPath: String) -> String {
        guard !repositoryPath.isEmpty else {
            return ""
        }

        let trackedResult = executeGitCommand(in: repositoryPath, args: ["diff", "--", "."])
        let trackedDiff = trackedResult.failure ? "" : trackedResult.output
        let untrackedDiff = diffForUntrackedFiles(at: repositoryPath)
        return [trackedDiff, untrackedDiff]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    func diffAll(in repositoryPath: String) -> String {
        let stagedDiff = diffStaged(in: repositoryPath)
        let unstagedDiff = diffUnstaged(in: repositoryPath)
        return [stagedDiff, unstagedDiff]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    func diffStagedAsync(in repositoryPath: String) async -> String {
        guard !repositoryPath.isEmpty else { return "" }
        return await runOnBackground {
            let result = self.executeGitCommand(in: repositoryPath, args: ["diff", "--cached", "--", "."])
            return result.failure ? "" : result.output
        }
    }

    func diffUnstagedAsync(in repositoryPath: String) async -> String {
        guard !repositoryPath.isEmpty else { return "" }
        return await runOnBackground {
            let trackedResult = self.executeGitCommand(in: repositoryPath, args: ["diff", "--", "."])
            let trackedDiff = trackedResult.failure ? "" : trackedResult.output
            let untrackedDiff = self.diffForUntrackedFiles(at: repositoryPath)
            return [trackedDiff, untrackedDiff]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        }
    }

    func diffAllAsync(in repositoryPath: String) async -> String {
        async let stagedDiff = diffStagedAsync(in: repositoryPath)
        async let unstagedDiff = diffUnstagedAsync(in: repositoryPath)
        return await [stagedDiff, unstagedDiff]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    func hasUncommittedChanges(in repositoryPath: String) -> Bool {
        guard !repositoryPath.isEmpty else {
            return false
        }

        return !executeGitCommand(in: repositoryPath, args: ["status", "--porcelain"])
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func hasUncommittedChangesAsync(in repositoryPath: String) async -> Bool {
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

    private nonisolated func diffForUntrackedFiles(at repositoryPath: String) -> String {
        let path = repositoryPath
        let untrackedResult = executeGitCommand(in: path, args: ["ls-files", "--others", "--exclude-standard"])
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
            let diffResult = executeGitCommand(in: path, args: ["diff", "--no-index", "--", "/dev/null", file])
            let output = diffResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return "diff --git a/\(file) b/\(file)\nnew file mode 100644\n+<unable to render diff>"
            }
            return output
        }

        return sections.joined(separator: "\n\n")
    }
}
