import Foundation

/// Owns index mutations for an explicit repository path; GitManager owns refresh publication.
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
}
