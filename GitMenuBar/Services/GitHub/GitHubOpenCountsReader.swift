import Foundation

struct GitHubOpenCountsReadResult: Equatable, Sendable {
    let openPullRequestCount: Int?
    let openIssueCount: Int?
    let unavailableReason: GitHubStatusUnavailableReason?

    static func unavailable(_ reason: GitHubStatusUnavailableReason) -> Self {
        Self(openPullRequestCount: nil, openIssueCount: nil, unavailableReason: reason)
    }
}

struct GitHubOpenCountsReader {
    private struct RawGraphQLResponse: Decodable {
        let data: RawGraphQLData?
        let errors: [RawGraphQLError]?
    }

    private struct RawGraphQLData: Decodable {
        let repository: RawRepository?
    }

    private struct RawRepository: Decodable {
        let pullRequests: RawCount
        let issues: RawCount
    }

    private struct RawCount: Decodable {
        let totalCount: Int
    }

    private struct RawGraphQLError: Decodable {}

    private static let query = "query($owner:String!,$name:String!){repository(owner:$owner,name:$name){pullRequests(states:OPEN){totalCount} issues(states:OPEN){totalCount}}}"

    let runner: GitCommandRunner

    func read(projectPath: String) -> GitHubOpenCountsReadResult {
        let remote = runner.runGitCommand(in: projectPath, args: ["remote", "get-url", "origin"])
        guard !remote.failure, let reference = GitHubRemoteURLParser.parse(remote.output) else {
            return .unavailable(.notGitHubRemote)
        }
        guard let ghPath = GitHubPullRequestStatusReader.githubCLIPath else {
            return .unavailable(.gitHubCLIMissing)
        }

        let result = runner.runCommand(
            in: projectPath,
            executable: ghPath,
            args: [
                "api", "graphql",
                "-F", "owner=\(reference.owner)",
                "-F", "name=\(reference.repository)",
                "-f", "query=\(Self.query)"
            ],
            additionalEnvironment: ["GH_PROMPT_DISABLED": "1", "GH_PAGER": "cat"]
        )
        guard !result.failure,
              let parsed = Self.parse(Data(result.output.utf8))
        else {
            return .unavailable(.commandFailed)
        }
        return parsed
    }

    static func parse(_ data: Data) -> GitHubOpenCountsReadResult? {
        guard let response = try? JSONDecoder().decode(RawGraphQLResponse.self, from: data),
              response.errors?.isEmpty ?? true,
              let repository = response.data?.repository,
              repository.pullRequests.totalCount >= 0,
              repository.issues.totalCount >= 0
        else {
            return nil
        }
        return GitHubOpenCountsReadResult(
            openPullRequestCount: repository.pullRequests.totalCount,
            openIssueCount: repository.issues.totalCount,
            unavailableReason: nil
        )
    }
}
