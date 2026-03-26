@testable import GitMenuBar
import XCTest

final class GitManagerCommitHistoryPaginationTests: XCTestCase {
    func testLoadMoreCommitHistoryIncreasesFetchLimitBy25() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)

        for index in 1 ... 60 {
            let fileURL = repoURL.appendingPathComponent("file-\(index).txt")
            try "value-\(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try runGit(["add", "."], in: repoURL)
            try runGit(["commit", "-m", "feat: commit \(index)"], in: repoURL)
        }

        try withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            gitManager.fetchCommitHistory(limit: 25)
            waitForHistoryUpdate(timeout: 6) {
                gitManager.commitHistoryLimit == 25 && gitManager.commitHistory.count == 25
            }

            gitManager.loadMoreCommitHistory(batchSize: 25)
            waitForHistoryUpdate(timeout: 6) {
                gitManager.commitHistoryLimit == 50 && gitManager.commitHistory.count == 50
            }

            XCTAssertTrue(gitManager.canLoadMoreCommitHistory)

            gitManager.loadMoreCommitHistory(batchSize: 25)
            waitForHistoryUpdate(timeout: 6) {
                gitManager.commitHistoryLimit == 75 && gitManager.commitHistory.count == 61
            }

            XCTAssertFalse(gitManager.canLoadMoreCommitHistory)
        }
    }

    func testFetchCommitHistoryExcludesReflogOnlyCommitsByDefault() throws {
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

        try withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            gitManager.fetchCommitHistory(limit: 10, includeReflog: false)
            waitForHistoryUpdate(timeout: 6) {
                gitManager.commitHistory.count == 2
            }

            XCTAssertEqual(
                gitManager.commitHistory.map(\.subject),
                ["feat: visible commit", "chore: initial"]
            )
        }
    }

    func testResetToCommitIncludesReflogCommitsForRestore() throws {
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

        try withGitRepoPath(repoURL.path) {
            let gitManager = GitManager()

            waitForHistoryUpdate(timeout: 6) {
                gitManager.commitHistory.count >= 3
            }

            gitManager.resetToCommit(targetHash)

            waitForHistoryUpdate(timeout: 6) {
                gitManager.currentHash == targetHash &&
                    gitManager.commitHistory.contains(where: { $0.subject == "feat: future commit" })
            }

            XCTAssertEqual(gitManager.currentHash, targetHash)
            XCTAssertTrue(gitManager.commitHistory.contains(where: { $0.subject == "feat: future commit" }))
            XCTAssertTrue(gitManager.commitHistory.contains(where: { $0.subject == "feat: visible commit" }))
        }
    }

    private func waitForHistoryUpdate(timeout: TimeInterval, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        XCTFail("Timed out waiting for commit history update.")
    }
}
