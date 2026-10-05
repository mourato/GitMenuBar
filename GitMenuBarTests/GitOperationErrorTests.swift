@testable import GitMenuBar
import XCTest

final class GitOperationErrorTests: XCTestCase {
    func testLocalizedDescriptionPreservesGitMessages() {
        let missingRepository: Error = GitOperationError.noRepository
        XCTAssertEqual(missingRepository.localizedDescription, "No repository path configured")

        let commandFailure: Error = GitOperationError.commandFailed("Failed to commit: fatal: index is locked\n")
        XCTAssertEqual(commandFailure.localizedDescription, "Failed to commit: fatal: index is locked\n")
    }
}
