@testable import GitMenuBar
import XCTest

final class GitManagerCommitMessageRewriteTests: XCTestCase {
    func testRewriteHeadCommitMessageUpdatesHead() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nhead rewrite\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoURL)
        try runGit(["commit", "-m", "feat: original head"], in: repoURL)

        try withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            let expectation = expectation(description: "rewrite head commit")
            gitManager.rewriteCommitMessage(commitHash: currentHeadHash(in: repoURL), newMessage: "feat: rewritten head") { result in
                XCTAssertTrue(result.isSuccess)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10)

            let headSubject = try runGit(["log", "-1", "--pretty=%s"], in: repoURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(headSubject, "feat: rewritten head")
        }
    }

    func testRewriteEarlierCommitMessagePreservesDescendants() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)

        try appendCommit(named: "second.txt", contents: "second\n", message: "feat: second", in: repoURL)
        let targetHash = currentHeadHash(in: repoURL)
        try appendCommit(named: "third.txt", contents: "third\n", message: "feat: third", in: repoURL)

        try withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            let expectation = expectation(description: "rewrite historical commit")
            gitManager.rewriteCommitMessage(commitHash: targetHash, newMessage: "feat: rewritten second") { result in
                XCTAssertTrue(result.isSuccess)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 15)

            let subjects = try runGit(["log", "--pretty=%s", "-3"], in: repoURL)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
            XCTAssertEqual(subjects, ["feat: third", "feat: rewritten second", "chore: initial"])
        }
    }

    func testRewriteCommitMessageRejectsMergeCommits() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let defaultBranch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["checkout", "-b", "feature/history"], in: repoURL)
        try appendCommit(named: "feature.txt", contents: "feature\n", message: "feat: feature branch", in: repoURL)
        try runGit(["checkout", defaultBranch], in: repoURL)
        try appendCommit(named: "main.txt", contents: "main\n", message: "feat: main branch", in: repoURL)
        try runGit(["merge", "feature/history", "-m", "Merge branch 'feature/history'"], in: repoURL)

        try withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            let expectation = expectation(description: "reject merge commit rewrite")
            gitManager.rewriteCommitMessage(commitHash: currentHeadHash(in: repoURL), newMessage: "feat: rewrite merge") { result in
                switch result {
                case .success:
                    XCTFail("Expected merge commit rewrite to fail")
                case .failure:
                    break
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10)
        }
    }

    func testIsCommitPublishedToUpstreamDetectsRemoteCommit() throws {
        let remoteDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMenuBarTests")
            .appendingPathComponent(#function + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: remoteDirectory, withIntermediateDirectories: true)

        let remoteURL = remoteDirectory.appendingPathComponent("origin.git")
        try runGit(["init", "--bare", remoteURL.path], in: remoteDirectory)

        let repoURL = try createTemporaryGitRepository(testName: #function + "-local")
        try runGit(["remote", "add", "origin", remoteURL.path], in: repoURL)
        try runGit(["push", "-u", "origin", "HEAD"], in: repoURL)

        try appendCommit(named: "local.txt", contents: "local only\n", message: "feat: local only", in: repoURL)
        let publishedHash = try runGit(["rev-parse", "HEAD~1"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localOnlyHash = currentHeadHash(in: repoURL)

        try withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            let publishedExpectation = expectation(description: "published commit detected")
            gitManager.isCommitPublishedToUpstream(publishedHash) { result in
                XCTAssertEqual(try? result.get(), true)
                publishedExpectation.fulfill()
            }

            let localExpectation = expectation(description: "local commit not published")
            gitManager.isCommitPublishedToUpstream(localOnlyHash) { result in
                XCTAssertEqual(try? result.get(), false)
                localExpectation.fulfill()
            }

            wait(for: [publishedExpectation, localExpectation], timeout: 10)
        }
    }

    private func appendCommit(named fileName: String, contents: String, message: String, in repoURL: URL) throws {
        let fileURL = repoURL.appendingPathComponent(fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", fileName], in: repoURL)
        try runGit(["commit", "-m", message], in: repoURL)
    }

    private func currentHeadHash(in repoURL: URL) -> String {
        (try? runGit(["rev-parse", "HEAD"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }
}

private extension Result where Success == Void {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }

        return false
    }
}
