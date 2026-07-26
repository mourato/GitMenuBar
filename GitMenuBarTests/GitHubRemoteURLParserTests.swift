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

    func testBuildsCommitURLFromHTTPSRemote() {
        let url = GitHubRemoteURLParser.commitURL(
            remoteURL: "https://github.com/octocat/Hello-World.git",
            sha: "abc123"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://github.com/octocat/Hello-World/commit/abc123"
        )
    }

    func testBuildsCommitURLFromSSHRemote() {
        let url = GitHubRemoteURLParser.commitURL(
            remoteURL: "git@github.com:octocat/Hello-World.git",
            sha: "abc123"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://github.com/octocat/Hello-World/commit/abc123"
        )
    }

    func testBuildsBlobURLWithPercentEncodedPathSegments() {
        let url = GitHubRemoteURLParser.blobURL(
            remoteURL: "https://github.com/octocat/Hello-World.git",
            sha: "abc123",
            path: "Sources/My Feature/file name.swift"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://github.com/octocat/Hello-World/blob/abc123/Sources/My%20Feature/file%20name.swift"
        )
    }

    func testBuildsBlobURLFromExplicitOwnerAndRepository() {
        let url = GitHubRemoteURLParser.blobURL(
            owner: "octocat",
            repository: "Hello-World",
            sha: "abc123",
            path: "README.md"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://github.com/octocat/Hello-World/blob/abc123/README.md"
        )
    }

    func testReturnsNilBlobURLForEmptyPath() {
        XCTAssertNil(
            GitHubRemoteURLParser.blobURL(
                remoteURL: "https://github.com/octocat/Hello-World.git",
                sha: "abc123",
                path: ""
            )
        )
    }
}
