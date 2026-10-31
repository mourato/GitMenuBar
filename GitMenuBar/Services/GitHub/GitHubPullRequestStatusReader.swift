import Foundation

struct GitHubPullRequestReadResult: Equatable, Sendable {
    let pullRequests: [GitHubPullRequestSummary]
    let openCount: Int?
    let unavailableReason: GitHubStatusUnavailableReason?

    static func unavailable(_ reason: GitHubStatusUnavailableReason) -> Self {
        Self(pullRequests: [], openCount: nil, unavailableReason: reason)
    }
}

struct GitHubPullRequestStatusReader {
    private static let detailLimit = 20
    private static let countLimit = 1000

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

    func read(projectPath: String) -> GitHubPullRequestReadResult {
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
                "pr", "list", "--state", "open", "--limit", "\(Self.countLimit)",
                "--json", "number,title,headRefName,isDraft,reviewDecision,statusCheckRollup,url"
            ],
            additionalEnvironment: ["GH_PROMPT_DISABLED": "1", "GH_PAGER": "cat"]
        )
        guard !result.failure,
              let parsed = Self.parseStatus(Data(result.output.utf8))
        else {
            return .unavailable(.commandFailed)
        }
        return parsed
    }

    static func parse(_ data: Data) -> [GitHubPullRequestSummary] {
        parseStatus(data)?.pullRequests ?? []
    }

    static func parseStatus(_ data: Data) -> GitHubPullRequestReadResult? {
        guard let rawPullRequests = try? JSONDecoder().decode([RawPullRequest].self, from: data) else {
            return nil
        }
        let pullRequests = rawPullRequests.prefix(Self.detailLimit).map { pullRequest in
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
        return GitHubPullRequestReadResult(
            pullRequests: Array(pullRequests),
            openCount: rawPullRequests.count,
            unavailableReason: nil
        )
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
