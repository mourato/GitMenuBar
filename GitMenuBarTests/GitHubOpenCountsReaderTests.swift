@testable import GitMenuBar
import XCTest

final class GitHubOpenCountsReaderTests: XCTestCase {
    func testParsesGitHubGraphQLCountsAndRejectsInvalidResponses() throws {
        let result = try XCTUnwrap(
            GitHubOpenCountsReader.parse(
                Data("{\"data\":{\"repository\":{\"pullRequests\":{\"totalCount\":7},\"issues\":{\"totalCount\":11}}}}".utf8)
            )
        )
        XCTAssertEqual(result.openPullRequestCount, 7)
        XCTAssertEqual(result.openIssueCount, 11)
        XCTAssertNil(result.unavailableReason)
        let withWarnings = "{\"errors\":[{\"message\":\"notice\"}],\"data\":{\"repository\":"
            + "{\"pullRequests\":{\"totalCount\":2},\"issues\":{\"totalCount\":3}}}}"
        XCTAssertEqual(GitHubOpenCountsReader.parse(Data(withWarnings.utf8))?.openIssueCount, 3)
        for invalid in [
            "{\"errors\":[{\"message\":\"rate limit\"}],\"data\":null}",
            "{\"data\":{\"repository\":null}}",
            "malformed"
        ] {
            XCTAssertNil(GitHubOpenCountsReader.parse(Data(invalid.utf8)))
        }
    }

    func testCombinesGitHubAvailabilityReasonsAndCounts() {
        let pullRequests = GitHubPullRequestReadResult.unavailable(.notGitHubRemote)
        let issues = GitHubOpenCountsReadResult.unavailable(.notGitHubRemote)
        XCTAssertEqual(
            ProjectStatusReader.combine(pullRequestStatus: pullRequests, countsStatus: issues).unavailableReason,
            .notGitHubRemote
        )

        let availablePullRequests = GitHubPullRequestReadResult(pullRequests: [], unavailableReason: nil)
        let missingCLI = GitHubOpenCountsReadResult(openPullRequestCount: nil, openIssueCount: nil, unavailableReason: .gitHubCLIMissing)
        XCTAssertEqual(
            ProjectStatusReader.combine(
                pullRequestStatus: availablePullRequests,
                countsStatus: missingCLI
            ).unavailableReason,
            .gitHubCLIMissing
        )
        let counts = ProjectStatusReader.combine(
            pullRequestStatus: GitHubPullRequestReadResult(pullRequests: [], unavailableReason: nil),
            countsStatus: GitHubOpenCountsReadResult(
                openPullRequestCount: 7, openIssueCount: 11, unavailableReason: nil
            )
        )
        XCTAssertEqual(counts.openPullRequestCount, 7)
        XCTAssertEqual(counts.openIssueCount, 11)
        XCTAssertNil(counts.unavailableReason)
    }

    func testOpenCountsArgumentsKeepNamesAsStringsAndTargetEnterpriseHost() {
        let reference = GitHubRemoteReference(owner: "2024", repository: "@scoped")
        let publicArgs = GitHubOpenCountsReader.arguments(for: reference, host: "github.com")
        XCTAssertEqual(Array(publicArgs.prefix(6)), ["api", "graphql", "-f", "owner=2024", "-f", "name=@scoped"])
        XCTAssertFalse(publicArgs.contains("-F"))
        XCTAssertFalse(publicArgs.contains("--hostname"))

        let enterpriseURL = "https://acme.github.com/team/app.git"
        let enterpriseArgs = GitHubOpenCountsReader.arguments(
            for: GitHubRemoteReference(owner: "team", repository: "app"),
            host: GitHubRemoteURLParser.host(enterpriseURL)
        )
        XCTAssertEqual(Array(enterpriseArgs.prefix(4)), ["api", "graphql", "--hostname", "acme.github.com"])
        XCTAssertEqual(GitHubRemoteURLParser.host("git@github.com:team/app.git"), "github.com")
    }

    func testPartialGitHubFailureKeepsDetailsAndCountsIndependently() {
        let pullRequest = GitHubPullRequestSummary(
            number: 7,
            title: "Open pull request",
            headBranch: "feature/counts",
            isDraft: false,
            reviewState: .reviewRequired,
            checksState: .pending,
            url: "https://github.com/example/project/pull/7"
        )
        let pullRequests = GitHubPullRequestReadResult(pullRequests: [pullRequest], unavailableReason: nil)
        let failedCounts = GitHubOpenCountsReadResult.unavailable(.commandFailed)
        let result = ProjectStatusReader.combine(
            pullRequestStatus: pullRequests,
            countsStatus: failedCounts
        )
        XCTAssertEqual(result.pullRequests, [pullRequest])
        XCTAssertNil(result.openPullRequestCount)
        XCTAssertNil(result.openIssueCount)
        XCTAssertEqual(result.unavailableReason, .commandFailed)
        let reverseResult = ProjectStatusReader.combine(
            pullRequestStatus: .unavailable(.commandFailed),
            countsStatus: GitHubOpenCountsReadResult(
                openPullRequestCount: 7, openIssueCount: 11, unavailableReason: nil
            )
        )
        XCTAssertEqual(reverseResult.pullRequests, [])
        XCTAssertEqual(reverseResult.openPullRequestCount, 7)
        XCTAssertEqual(reverseResult.openIssueCount, 11)
        XCTAssertNil(reverseResult.unavailableReason)
    }
}
