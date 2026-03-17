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
