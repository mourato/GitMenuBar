@testable import GitMenuBar
import XCTest

final class GitHubRemoteURLParserTests: XCTestCase {
    func testParsesHTTPSRemoteURL() {
        let reference = GitHubRemoteURLParser.parse("https://github.com/octocat/Hello-World.git")

        XCTAssertEqual(reference, GitHubRemoteReference(owner: "octocat", repository: "Hello-World"))
    }

    func testParsesSSHRemoteURL() {
        let reference = GitHubRemoteURLParser.parse("git@github.com:octocat/Hello-World.git")

        XCTAssertEqual(reference, GitHubRemoteReference(owner: "octocat", repository: "Hello-World"))
    }

    func testReturnsNilForInvalidURL() {
        XCTAssertNil(GitHubRemoteURLParser.parse("https://example.com/octocat/Hello-World"))
        XCTAssertNil(GitHubRemoteURLParser.parse("not-a-url"))
    }
}
