import Foundation

final class GitAtomicCommitService: ObservableObject {
    private let repositoryContext: GitRepositoryContext
    private let commandRunner: GitCommandRunner

    init(repositoryContext: GitRepositoryContext, commandRunner: GitCommandRunner) {
        self.repositoryContext = repositoryContext
        self.commandRunner = commandRunner
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

    private func makeMissingRepositoryError() -> NSError {
        GitExecution.missingRepositoryError()
    }

    /// Returns a map of changed file path -> diff string for all changed files.
    func diffForChangedFilesAsync(changedFiles: [WorkingTreeFile]) async -> [String: String] {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return [:] }

        return await runOnBackground {
            var result: [String: String] = [:]
            let files = changedFiles.map(\.path)
            for file in files {
                let diffResult = self.executeGitCommand(
                    in: repositoryPath,
                    args: ["diff", "--", file]
                )
                if !diffResult.failure {
                    result[file] = diffResult.output
                }
            }
            return result
        }
    }

    /// Stage specific files and commit with the given message.
    func commitAtomicGroupAsync(
        files: [String],
        message: String
    ) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(makeMissingRepositoryError())
        }

        guard !files.isEmpty else {
            return .failure(NSError(
                domain: "GitManager",
                code: 30,
                userInfo: [NSLocalizedDescriptionKey: "No files to commit"]
            ))
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return .failure(NSError(
                domain: "GitManager",
                code: 33,
                userInfo: [NSLocalizedDescriptionKey: "Commit message cannot be empty"]
            ))
        }

        _ = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["restore", "--staged", "--", "."])
        }

        let stageArgs = ["add", "--"] + files
        let stageResult = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: stageArgs)
        }
        guard !stageResult.failure else {
            return .failure(NSError(
                domain: "GitManager",
                code: 31,
                userInfo: [NSLocalizedDescriptionKey: "Failed to stage files: \(stageResult.output)"]
            ))
        }

        let commitResult = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["commit", "--no-gpg-sign", "-m", trimmedMessage])
        }
        guard !commitResult.failure else {
            return .failure(NSError(
                domain: "GitManager",
                code: 32,
                userInfo: [NSLocalizedDescriptionKey: "Failed to commit: \(commitResult.output)"]
            ))
        }

        return .success(())
    }

    /// Execute the full atomic commit sequence for a list of groups.
    func performAtomicCommitsAsync(
        groups: [AtomicCommitGroup],
        changedFiles: [WorkingTreeFile],
        stagedFiles: [WorkingTreeFile],
        uncommittedFiles: [String]
    ) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else {
            return .failure(makeMissingRepositoryError())
        }

        let originalHeadResult = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "HEAD"])
        }
        guard !originalHeadResult.failure else {
            return .failure(NSError(
                domain: "GitManager",
                code: 34,
                userInfo: [NSLocalizedDescriptionKey: "Failed to capture current HEAD: \(originalHeadResult.output)"]
            ))
        }
        let originalHead = originalHeadResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        let allowedFiles = Set(changedFiles.map(\.path) + stagedFiles.map(\.path) + uncommittedFiles)
        let plan: AtomicCommitPlan
        do {
            plan = try AtomicCommitPlan(groups: groups, allowedFiles: allowedFiles)
        } catch {
            return .failure(error)
        }

        for group in plan.groups {
            let result = await commitAtomicGroupAsync(files: group.files, message: group.message)
            if case let .failure(error) = result {
                await rollbackAtomicCommits(to: originalHead, repositoryPath: repositoryPath)
                return .failure(error)
            }
        }

        return .success(())
    }

    private func rollbackAtomicCommits(to originalHead: String, repositoryPath: String) async {
        await runOnBackground {
            _ = self.executeGitCommand(in: repositoryPath, args: ["reset", "--mixed", originalHead])
        }
    }
}
