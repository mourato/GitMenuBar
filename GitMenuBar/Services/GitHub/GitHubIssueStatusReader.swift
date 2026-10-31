import Foundation

struct GitHubIssueReadResult: Equatable, Sendable {
    let openCount: Int?
    let unavailableReason: GitHubStatusUnavailableReason?

    static func unavailable(_ reason: GitHubStatusUnavailableReason) -> Self {
        Self(openCount: nil, unavailableReason: reason)
    }
}

struct GitHubIssueStatusReader {
    private static let countLimit = 1000

    private struct RawIssue: Decodable {
        let number: Int
    }

    let runner: GitCommandRunner

    func read(projectPath: String) -> GitHubIssueReadResult {
        let remote = runner.runGitCommand(in: projectPath, args: ["remote", "get-url", "origin"])
        guard !remote.failure, GitHubRemoteURLParser.parse(remote.output) != nil else {
            return .unavailable(.notGitHubRemote)
        }
        guard let ghPath = Self.githubCLIPath else {
            return .unavailable(.gitHubCLIMissing)
        }

        let result = runner.runCommand(
            in: projectPath,
            executable: ghPath,
            args: [
                "issue", "list", "--state", "open", "--search", "is:issue", "--limit", "\(Self.countLimit)",
                "--json", "number"
            ],
            additionalEnvironment: ["GH_PROMPT_DISABLED": "1", "GH_PAGER": "cat"]
        )
        guard !result.failure,
              let openCount = Self.parse(Data(result.output.utf8))
        else {
            return .unavailable(.commandFailed)
        }
        return GitHubIssueReadResult(openCount: openCount, unavailableReason: nil)
    }

    static func parse(_ data: Data) -> Int? {
        guard let issues = try? JSONDecoder().decode([RawIssue].self, from: data) else {
            return nil
        }
        return issues.count
    }

    private static var githubCLIPath: String? {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { "\($0)/gh" }
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] + pathEntries
        return candidates
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }
}
