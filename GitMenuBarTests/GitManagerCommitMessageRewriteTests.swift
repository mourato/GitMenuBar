@testable import GitMenuBar
import XCTest

@MainActor
final class GitManagerCommitMessageRewriteTests: XCTestCase {
    func testRewriteHeadCommitMessageUpdatesHead() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nhead rewrite\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoURL)
        try runGit(["commit", "-m", "feat: original head"], in: repoURL)

        try await withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            try await gitManager.rewriteCommitMessageAsync(commitHash: currentHeadHash(in: repoURL), newMessage: "feat: rewritten head")

            let headSubject = try runGit(["log", "-1", "--pretty=%s"], in: repoURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(headSubject, "feat: rewritten head")
        }
    }

    func testRewriteEarlierCommitMessagePreservesDescendants() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)

        try appendCommit(named: "second.txt", contents: "second\n", message: "feat: second", in: repoURL)
        let targetHash = currentHeadHash(in: repoURL)
        try appendCommit(named: "third.txt", contents: "third\n", message: "feat: third", in: repoURL)

        try await withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            try await gitManager.rewriteCommitMessageAsync(commitHash: targetHash, newMessage: "feat: rewritten second")

            let subjects = try runGit(["log", "--pretty=%s", "-3"], in: repoURL)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
            XCTAssertEqual(subjects, ["feat: third", "feat: rewritten second", "chore: initial"])
        }
    }

    func testRewriteCommitMessageRejectsMergeCommits() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let defaultBranch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try runGit(["checkout", "-b", "feature/history"], in: repoURL)
        try appendCommit(named: "feature.txt", contents: "feature\n", message: "feat: feature branch", in: repoURL)
        try runGit(["checkout", defaultBranch], in: repoURL)
        try appendCommit(named: "main.txt", contents: "main\n", message: "feat: main branch", in: repoURL)
        try runGit(["merge", "feature/history", "-m", "Merge branch 'feature/history'"], in: repoURL)

        try await withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            do {
                try await gitManager.rewriteCommitMessageAsync(commitHash: currentHeadHash(in: repoURL), newMessage: "feat: rewrite merge")
                XCTFail("Expected merge commit rewrite to fail")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("merge commits"))
            }
        }
    }

    func testIsCommitPublishedToUpstreamDetectsRemoteCommit() async throws {
        let remoteDirectory = try makeTemporaryTestDirectory(testName: #function)

        let remoteURL = remoteDirectory.appendingPathComponent("origin.git")
        try runGit(["init", "--bare", remoteURL.path], in: remoteDirectory)

        let repoURL = try createTemporaryGitRepository(testName: #function + "-local")
        try runGit(["remote", "add", "origin", remoteURL.path], in: repoURL)
        try runGit(["push", "-u", "origin", "HEAD"], in: repoURL)

        try appendCommit(named: "local.txt", contents: "local only\n", message: "feat: local only", in: repoURL)
        let publishedHash = try runGit(["rev-parse", "HEAD~1"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localOnlyHash = currentHeadHash(in: repoURL)

        try await withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            let published = try await gitManager.isCommitPublishedToUpstreamAsync(publishedHash)
            let local = try await gitManager.isCommitPublishedToUpstreamAsync(localOnlyHash)
            XCTAssertTrue(published)
            XCTAssertFalse(local)
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
