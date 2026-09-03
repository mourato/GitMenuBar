import Foundation

final class GitStashService: @unchecked Sendable {
    private let commandRunner: GitCommandRunner

    init(commandRunner: GitCommandRunner) {
        self.commandRunner = commandRunner
    }

    static func parseStashList(_ output: String) -> [GitStashInfo] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var stashes: [GitStashInfo] = []
        for record in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = record.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else {
                continue
            }

            let hash = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let displayRef = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let timestamp = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isStashHash(hash), displayRef.hasPrefix("stash@{") else {
                continue
            }

            stashes.append(
                GitStashInfo(
                    hash: hash,
                    displayRef: displayRef,
                    subject: subject,
                    branchName: branchName(from: subject),
                    createdAt: TimeInterval(timestamp).map(Date.init(timeIntervalSince1970:))
                )
            )
        }
        return stashes
    }

    func listStashes(in repositoryPath: String) -> [GitStashInfo] {
        guard !repositoryPath.isEmpty else {
            return []
        }

        let result = GitExecution.executeGitCommand(
            in: repositoryPath,
            args: ["stash", "list", "--format=%H%x00%gd%x00%s%x00%ct"],
            using: commandRunner
        )
        guard !result.failure else {
            return []
        }
        return Self.parseStashList(result.output)
    }

    func applyStash(hash: String, in repositoryPath: String) -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }
        guard let stash = listStashes(in: repositoryPath).first(where: { $0.hash == hash }) else {
            return .failure(stashError("The selected stash is no longer in this repository."))
        }

        let result = GitExecution.executeGitCommand(
            in: repositoryPath,
            args: ["stash", "apply", stash.hash],
            using: commandRunner
        )
        guard !result.failure else {
            return .failure(stashError(Self.userFacingMessage(from: result.output)))
        }
        return .success(())
    }

    func dropStash(hash: String, in repositoryPath: String) -> Result<Void, Error> {
        guard !repositoryPath.isEmpty else {
            return .failure(GitExecution.missingRepositoryError())
        }
        guard let stash = listStashes(in: repositoryPath).first(where: { $0.hash == hash }) else {
            return .failure(stashError("The selected stash is no longer in this repository."))
        }

        let result = GitExecution.executeGitCommand(
            in: repositoryPath,
            args: ["stash", "drop", "--quiet", stash.displayRef],
            using: commandRunner
        )
        guard !result.failure else {
            return .failure(stashError(Self.userFacingMessage(from: result.output)))
        }
        return .success(())
    }

    static func userFacingMessage(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let lowered = firstLine.lowercased()
        if firstLine.isEmpty || lowered.contains("password") || lowered.contains("token")
            || lowered.contains("authorization")
        {
            return "Git command failed."
        }
        return firstLine
    }

    private static func isStashHash(_ value: String) -> Bool {
        value.count >= 7 && value.allSatisfy(\.isHexDigit)
    }

    private static func branchName(from subject: String) -> String? {
        if subject.hasPrefix("WIP on "), let colon = subject.firstIndex(of: ":") {
            let name = subject[subject.index(subject.startIndex, offsetBy: 7) ..< colon]
            return name.isEmpty ? nil : String(name)
        }
        if subject.hasPrefix("On "), let colon = subject.firstIndex(of: ":") {
            let name = subject[subject.index(subject.startIndex, offsetBy: 3) ..< colon]
            return name.isEmpty ? nil : String(name)
        }
        return nil
    }

    private func stashError(_ message: String) -> NSError {
        NSError(
            domain: "GitStashService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
