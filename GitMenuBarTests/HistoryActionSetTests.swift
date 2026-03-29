@testable import GitMenuBar
import XCTest

final class HistoryActionSetTests: XCTestCase {
    func testResolveActionSetReflectsRemoteAndCommitState() {
        let commit = Commit(
            id: "abc123",
            shortHash: "abc123",
            subject: "feat: test",
            body: "",
            authorName: "Renato",
            authorEmail: "renato@example.com",
            committedAt: .now,
            stats: CommitStats(filesChanged: 1, insertions: 2, deletions: 1),
            changedFiles: []
        )

        let actionSet = HistoryActionSet(
            commit: commit,
            currentHash: "def456",
            remoteUrl: "git@github.com:saihgupr/GitMenuBar.git",
            isCommitInFuture: true
        )

        XCTAssertEqual(
            actionSet.commitURL?.absoluteString,
            "https://github.com/saihgupr/GitMenuBar/commit/abc123"
        )
        XCTAssertTrue(actionSet.canOpenOnGitHub)
        XCTAssertTrue(actionSet.canEditMessage)
        XCTAssertTrue(actionSet.canGenerateMessage)
        XCTAssertTrue(actionSet.canRestore)
        XCTAssertTrue(actionSet.isFutureCommit)
        XCTAssertFalse(actionSet.isCurrentCommit)
    }

    func testResolveActionSetDisablesRemoteAndEditActionsForMergeCurrentCommit() {
        let commit = Commit(
            id: "abc123",
            shortHash: "abc123",
            subject: "Merge branch 'feature'",
            body: "",
            authorName: "Renato",
            authorEmail: "renato@example.com",
            committedAt: .now,
            isMergeCommit: true,
            stats: CommitStats(filesChanged: 1, insertions: 2, deletions: 1),
            changedFiles: []
        )

        let actionSet = HistoryActionSet(
            commit: commit,
            currentHash: "abc123",
            remoteUrl: "",
            isCommitInFuture: false
        )

        XCTAssertNil(actionSet.commitURL)
        XCTAssertFalse(actionSet.canOpenOnGitHub)
        XCTAssertFalse(actionSet.canEditMessage)
        XCTAssertFalse(actionSet.canGenerateMessage)
        XCTAssertFalse(actionSet.canRestore)
        XCTAssertFalse(actionSet.isFutureCommit)
        XCTAssertTrue(actionSet.isCurrentCommit)
    }
}
