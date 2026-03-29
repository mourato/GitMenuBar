@testable import GitMenuBar
import XCTest

final class RepositoryActionSetTests: XCTestCase {
    func testActionSetReflectsRepositoryState() {
        let actionSet = RepositoryActionSet(
            currentRepoPath: "/tmp/repo",
            remoteUrl: "git@github.com:saihgupr/GitMenuBar.git",
            isGitHubAuthenticated: true,
            isPrivate: true
        )

        XCTAssertTrue(actionSet.canRevealInFinder)
        XCTAssertTrue(actionSet.canOpenOnGitHub)
        XCTAssertTrue(actionSet.canShowRepositoryOptions)
        XCTAssertEqual(actionSet.visibilityActionTitle, "Make Public")
        XCTAssertEqual(actionSet.visibilityConfirmationTitle, "Make Repository Public?")
    }

    func testActionSetDisablesRemoteOnlyActionsWithoutRemote() {
        let actionSet = RepositoryActionSet(
            currentRepoPath: "",
            remoteUrl: "",
            isGitHubAuthenticated: false,
            isPrivate: false
        )

        XCTAssertFalse(actionSet.canRevealInFinder)
        XCTAssertFalse(actionSet.canOpenOnGitHub)
        XCTAssertFalse(actionSet.canShowRepositoryOptions)
        XCTAssertEqual(actionSet.visibilityActionTitle, "Make Private")
        XCTAssertEqual(actionSet.visibilityStatusDescription, "This repository is currently public.")
    }
}
