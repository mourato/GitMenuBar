@testable import GitMenuBar
import XCTest

@MainActor
final class GitManagerCommitHistoryPaginationTests: XCTestCase {
    func testLoadMoreCommitHistoryIncreasesFetchLimitBy25() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)

        for index in 1 ... 60 {
            let fileURL = repoURL.appendingPathComponent("file-\(index).txt")
            try "value-\(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try runGit(["add", "."], in: repoURL)
            try runGit(["commit", "-m", "feat: commit \(index)"], in: repoURL)
        }

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        await gitManager.fetchCommitHistoryAsync(limit: 25)
        XCTAssertEqual(gitManager.commitHistoryLimit, 25)
        XCTAssertEqual(gitManager.commitHistory.count, 25)

        // Awaits the same fetch that loadMoreCommitHistory starts; the +25 step itself is not covered here.
        await gitManager.fetchCommitHistoryAsync(limit: 50)
        XCTAssertEqual(gitManager.commitHistoryLimit, 50)
        XCTAssertEqual(gitManager.commitHistory.count, 50)

        XCTAssertTrue(gitManager.canLoadMoreCommitHistory)

        await gitManager.fetchCommitHistoryAsync(limit: 75)
        XCTAssertEqual(gitManager.commitHistoryLimit, 75)
        XCTAssertEqual(gitManager.commitHistory.count, 61)

        XCTAssertFalse(gitManager.canLoadMoreCommitHistory)
    }

    func testFetchCommitHistoryExcludesReflogOnlyCommitsByDefault() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)

        let visibleFileURL = repoURL.appendingPathComponent("visible.txt")
        try "visible\n".write(to: visibleFileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "feat: visible commit"], in: repoURL)

        let rewrittenFileURL = repoURL.appendingPathComponent("rewritten.txt")
        try "rewritten\n".write(to: rewrittenFileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "feat: reflog only"], in: repoURL)

        try runGit(["reset", "--hard", "HEAD~1"], in: repoURL)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        await gitManager.fetchCommitHistoryAsync(limit: 10, includeReflog: false)
        await waitForObservedCondition(timeout: 15) {
            gitManager.commitHistory.count == 2
        }

        XCTAssertEqual(
            gitManager.commitHistory.map(\.subject),
            ["feat: visible commit", "chore: initial"]
        )
    }

    func testResetToCommitIncludesReflogCommitsForRestore() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)

        let visibleFileURL = repoURL.appendingPathComponent("visible.txt")
        try "visible\n".write(to: visibleFileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "feat: visible commit"], in: repoURL)

        let futureFileURL = repoURL.appendingPathComponent("future.txt")
        try "future\n".write(to: futureFileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "feat: future commit"], in: repoURL)

        let targetHash = try runGit(["rev-parse", "HEAD~1"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        await waitForObservedCondition(timeout: 15) {
            gitManager.commitHistory.count >= 3
        }

        try await gitManager.resetToCommitAsync(hash: targetHash, context: gitManager.makeRepositoryOperationContext()).get()

        await waitForObservedCondition(timeout: 15) {
            gitManager.currentHash == targetHash &&
                gitManager.commitHistory.contains(where: { $0.subject == "feat: future commit" })
        }

        XCTAssertEqual(gitManager.currentHash, targetHash)
        XCTAssertTrue(gitManager.commitHistory.contains(where: { $0.subject == "feat: future commit" }))
        XCTAssertTrue(gitManager.commitHistory.contains(where: { $0.subject == "feat: visible commit" }))
    }
}
