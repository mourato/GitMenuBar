import Foundation

struct GitHubPullRequestStatusReader {
    private struct RawPullRequest: Decodable {
        let number: Int
        let title: String
        let headRefName: String
        let isDraft: Bool
        let reviewDecision: String?
        let statusCheckRollup: [RawCheck]?
        let url: String
    }

    private struct RawCheck: Decodable {
        let state: String?
        let status: String?
        let conclusion: String?
    }

    let runner: GitCommandRunner

    func read(projectPath: String) -> [GitHubPullRequestSummary] {
        let remote = runner.runGitCommand(in: projectPath, args: ["remote", "get-url", "origin"])
        guard !remote.failure, GitHubRemoteURLParser.parse(remote.output) != nil,
              let ghPath = Self.githubCLIPath
        else {
            return []
        }

        let result = runner.runCommand(
            in: projectPath,
            executable: ghPath,
            args: [
                "pr", "list", "--state", "open", "--limit", "20",
                "--json", "number,title,headRefName,isDraft,reviewDecision,statusCheckRollup,url"
            ],
            additionalEnvironment: ["GH_PROMPT_DISABLED": "1", "GH_PAGER": "cat"]
        )
        guard !result.failure else { return [] }
        return Self.parse(Data(result.output.utf8))
    }

    static func parse(_ data: Data) -> [GitHubPullRequestSummary] {
        guard let rawPullRequests = try? JSONDecoder().decode([RawPullRequest].self, from: data) else {
            return []
        }
        return rawPullRequests.map { pullRequest in
            GitHubPullRequestSummary(
                number: pullRequest.number,
                title: pullRequest.title,
                headBranch: pullRequest.headRefName,
                isDraft: pullRequest.isDraft,
                reviewState: reviewState(for: pullRequest.reviewDecision),
                checksState: checksState(for: pullRequest.statusCheckRollup),
                url: pullRequest.url
            )
        }
    }

    private static func reviewState(for value: String?) -> GitHubPullRequestReviewState {
        switch value?.uppercased() {
        case "APPROVED":
            .approved
        case "CHANGES_REQUESTED":
            .changesRequested
        case "REVIEW_REQUIRED":
            .reviewRequired
        default:
            .unknown
        }
    }

    private static func checksState(for checks: [RawCheck]?) -> GitHubChecksState {
        guard let checks, !checks.isEmpty else { return .notRun }
        let states = Set(checks.compactMap { check in
            (check.state ?? check.conclusion ?? check.status)?.uppercased()
        })
        if states.isEmpty {
            return .unknown
        }
        if states.contains(where: {
            ["FAILURE", "ERROR", "STARTUP_FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STALE"].contains($0)
        }) {
            return .failing
        }
        if states.contains(where: { ["PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"].contains($0) }) {
            return .pending
        }
        if states.allSatisfy({ ["SUCCESS", "SKIPPED", "NEUTRAL", "EXPECTED"].contains($0) }) {
            return .passed
        }
        return .unknown
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
