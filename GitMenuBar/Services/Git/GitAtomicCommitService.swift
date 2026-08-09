import CryptoKit
import Foundation

@MainActor
final class GitAtomicCommitService: ObservableObject {
    private struct HunkExecutionContext {
        let snapshot: AtomicCommitSnapshot
        let originalHead: String
        let repositoryPath: String
        let environment: [String: String]
    }

    private nonisolated(unsafe) let repositoryContext: GitRepositoryContext
    private nonisolated(unsafe) let commandRunner: GitCommandRunner

    init(repositoryContext: GitRepositoryContext, commandRunner: GitCommandRunner) {
        self.repositoryContext = repositoryContext
        self.commandRunner = commandRunner
    }

    private var storedRepoPath: String {
        repositoryContext.repositoryPath
    }

    private func runOnBackground<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await GitExecution.runOnBackground(operation)
    }

    private func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await GitExecution.publishOnMainActor(update)
    }

    private nonisolated func executeGitCommand(
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

    func makeSnapshotAsync(files: [WorkingTreeFile]) async -> AtomicCommitSnapshot? {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return nil }
        let diffs = await diffForChangedFilesAsync(changedFiles: files)
        let headResult = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "HEAD"])
        }
        guard !headResult.failure else { return nil }
        let head = headResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["status", "--porcelain=v1"]).output
        }
        let fingerprint = Self.fingerprint(head: head, files: files, diffs: diffs, status: status)
        let hunks: [AtomicCommitHunk] = files.flatMap { file in
            guard file.status == .modified, let diff = diffs[file.path] else { return [] as [AtomicCommitHunk] }
            return GitDiffHunkParser.parse(path: file.path, diff: diff)
        }
        return AtomicCommitSnapshot(head: head, fingerprint: fingerprint, files: files, hunks: hunks)
    }

    private static func fingerprint(
        head: String,
        files: [WorkingTreeFile],
        diffs: [String: String],
        status: String
    ) -> String {
        let canonical = files.sorted { $0.path < $1.path }.map { file in
            "\(file.path)\u{0}\(file.status.rawValue)\u{0}\(diffs[file.path] ?? "")"
        }.joined(separator: "\u{1}") + "\u{2}" + head + "\u{3}" + status
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
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
        uncommittedFiles: [String],
        progress: ((Int, Int) -> Void)? = nil
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

        for (index, group) in plan.groups.enumerated() {
            progress?(index + 1, plan.groups.count)
            let result = await commitAtomicGroupAsync(files: group.files, message: group.message)
            if case let .failure(error) = result {
                await rollbackAtomicCommits(to: originalHead, repositoryPath: repositoryPath)
                return .failure(error)
            }
        }

        return .success(())
    }

    func performHunkCommitsAsync(
        groups: [AtomicCommitGroup],
        snapshot: AtomicCommitSnapshot,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> Result<Void, Error> {
        let repositoryPath = storedRepoPath
        guard !repositoryPath.isEmpty else { return .failure(makeMissingRepositoryError()) }
        let lockPathResult = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--git-path", "index.lock"])
        }
        guard !lockPathResult.failure else {
            return .failure(Self.hunkError("Could not resolve the repository Git index lock path."))
        }
        let lockPath = lockPathResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lockURL = lockPath.hasPrefix("/")
            ? URL(fileURLWithPath: lockPath)
            : URL(fileURLWithPath: repositoryPath).appendingPathComponent(lockPath)
        guard !FileManager.default.fileExists(atPath: lockURL.path) else {
            return .failure(Self.hunkError("Git index is locked; close other Git operations and try again."))
        }

        let staged = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["diff", "--cached", "--quiet"])
        }
        guard !staged.failure else {
            return .failure(Self.hunkError("Unstage existing changes before splitting hunks."))
        }

        guard let current = await makeSnapshotAsync(files: snapshot.files),
              current.head == snapshot.head,
              current.fingerprint == snapshot.fingerprint
        else {
            return .failure(Self.hunkError("The working tree changed; regenerate the atomic commit groups."))
        }

        let originalHeadResult = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "HEAD"])
        }
        guard !originalHeadResult.failure else { return .failure(Self.hunkError("Could not determine the current HEAD.")) }
        let originalHead = originalHeadResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan: AtomicCommitPlan
        do {
            plan = try AtomicCommitPlan(groups: groups, allowedFiles: snapshot.allowedFiles, hunksByID: snapshot.hunksByID)
        } catch { return .failure(error) }

        let temporaryIndex = FileManager.default.temporaryDirectory.appendingPathComponent("gitmenubar-index-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: temporaryIndex) }
        let environment = ["GIT_INDEX_FILE": temporaryIndex]
        let initialized = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["read-tree", originalHead], additionalEnvironment: environment)
        }
        guard !initialized.failure else { return .failure(Self.hunkError("Could not initialize the temporary Git index.")) }

        return await executeHunkGroups(
            plan.groups,
            context: HunkExecutionContext(
                snapshot: snapshot,
                originalHead: originalHead,
                repositoryPath: repositoryPath,
                environment: environment
            ),
            progress: progress
        )
    }

    private func executeHunkGroups(
        _ groups: [AtomicCommitGroup],
        context: HunkExecutionContext,
        progress: ((Int, Int) -> Void)?
    ) async -> Result<Void, Error> {
        for (index, group) in groups.enumerated() {
            progress?(index + 1, groups.count)
            let stageResult = await runOnBackground {
                self.stage(
                    group: group,
                    snapshot: context.snapshot,
                    repositoryPath: context.repositoryPath,
                    environment: context.environment
                )
            }
            guard !stageResult.failure else {
                await rollbackAtomicCommits(to: context.originalHead, repositoryPath: context.repositoryPath)
                return .failure(Self.hunkError("Git rejected group \(index + 1): \(stageResult.output)"))
            }
            let commit = await runOnBackground {
                self.executeGitCommand(
                    in: context.repositoryPath,
                    args: ["commit", "--no-gpg-sign", "-m", group.message],
                    additionalEnvironment: context.environment
                )
            }
            guard !commit.failure else {
                await rollbackAtomicCommits(to: context.originalHead, repositoryPath: context.repositoryPath)
                return .failure(Self.hunkError("Commit group \(index + 1) failed: \(commit.output)"))
            }
            if index + 1 < groups.count {
                let refreshed = await runOnBackground {
                    self.executeGitCommand(
                        in: context.repositoryPath,
                        args: ["read-tree", "HEAD"],
                        additionalEnvironment: context.environment
                    )
                }
                guard !refreshed.failure else {
                    await rollbackAtomicCommits(to: context.originalHead, repositoryPath: context.repositoryPath)
                    return .failure(Self.hunkError("Could not refresh the temporary Git index: \(refreshed.output)"))
                }
            }
        }
        let reconciled = await runOnBackground {
            self.executeGitCommand(in: context.repositoryPath, args: ["reset", "--mixed", "HEAD"])
        }
        guard !reconciled.failure else {
            await rollbackAtomicCommits(to: context.originalHead, repositoryPath: context.repositoryPath)
            return .failure(Self.hunkError("Could not reconcile the real Git index: \(reconciled.output)"))
        }
        return .success(())
    }

    private nonisolated func stage(
        group: AtomicCommitGroup,
        snapshot: AtomicCommitSnapshot,
        repositoryPath: String,
        environment: [String: String]
    ) -> (output: String, failure: Bool) {
        if !group.files.isEmpty {
            let result = executeGitCommand(in: repositoryPath, args: ["add", "--"] + group.files, additionalEnvironment: environment)
            if result.failure {
                return result
            }
        }
        for hunkID in group.hunks {
            guard let hunk = snapshot.hunksByID[hunkID] else { return ("Unknown hunk \(hunkID)", true) }
            let patchURL = FileManager.default.temporaryDirectory.appendingPathComponent("gitmenubar-patch-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: patchURL) }
            do {
                try hunk.patch.write(to: patchURL, atomically: true, encoding: .utf8)
            } catch { return (error.localizedDescription, true) }
            let check = executeGitCommand(in: repositoryPath, args: ["apply", "--cached", "--check", patchURL.path], additionalEnvironment: environment)
            if check.failure {
                return check
            }
            let applied = executeGitCommand(in: repositoryPath, args: ["apply", "--cached", patchURL.path], additionalEnvironment: environment)
            if applied.failure {
                return applied
            }
        }
        return ("", false)
    }

    private static func hunkError(_ message: String) -> NSError {
        NSError(domain: "GitManager", code: 35, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func rollbackAtomicCommits(to originalHead: String, repositoryPath: String) async {
        await runOnBackground {
            _ = self.executeGitCommand(in: repositoryPath, args: ["reset", "--mixed", originalHead])
        }
    }
}
