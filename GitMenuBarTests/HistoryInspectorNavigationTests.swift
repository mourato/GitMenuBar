@testable import GitMenuBar
import XCTest

final class HistoryInspectorNavigationTests: XCTestCase {
    func testDestinationMapsCommitSelection() {
        XCTAssertEqual(
            HistoryInspectorNavigation.destination(for: .commit(id: "abc123")),
            .commit(hash: "abc123")
        )
        XCTAssertNil(HistoryInspectorNavigation.destination(for: .history))
        XCTAssertNil(HistoryInspectorNavigation.destination(for: .workingTree))
        XCTAssertNil(HistoryInspectorNavigation.destination(for: nil))
    }

    func testCanConfirmResetRequiresDifferentCommitAndMatchingRepository() {
        XCTAssertTrue(
            HistoryInspectorNavigation.canConfirmReset(
                commitID: "abc123",
                currentHash: "def456",
                repositoryPath: "/tmp/repo",
                capturedRepositoryPath: "/tmp/repo"
            )
        )
        XCTAssertFalse(
            HistoryInspectorNavigation.canConfirmReset(
                commitID: "abc123",
                currentHash: "abc123",
                repositoryPath: "/tmp/repo",
                capturedRepositoryPath: "/tmp/repo"
            )
        )
        XCTAssertFalse(
            HistoryInspectorNavigation.canConfirmReset(
                commitID: "abc123",
                currentHash: "def456",
                repositoryPath: "/tmp/repo-a",
                capturedRepositoryPath: "/tmp/repo-b"
            )
        )
        XCTAssertFalse(
            HistoryInspectorNavigation.canConfirmReset(
                commitID: "",
                currentHash: "def456",
                repositoryPath: "/tmp/repo",
                capturedRepositoryPath: "/tmp/repo"
            )
        )
    }

    func testDestinationIdentityIsStable() {
        let destination = HistoryInspectorDestination.commit(hash: "abc123")
        XCTAssertEqual(destination.id, "commit:abc123")
        XCTAssertEqual(destination.hash, "abc123")
    }
}
