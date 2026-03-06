@testable import GitMenuBar
import XCTest

final class GitMenuBarTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
    }

    func testPrimaryActionShowsEnabledCommitWhenChangesAndMessageExist() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            hasCommitMessage: true,
            hasSyncWork: true,
            isCommitting: false,
            isGenerating: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertTrue(state.canCommit)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionKeepsCommitDisabledWhenMessageIsMissing() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            hasCommitMessage: false,
            hasSyncWork: true,
            isCommitting: false,
            isGenerating: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertTrue(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionEnablesSyncWhenAheadAndCommitInputsAreIdle() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: false,
            hasSyncWork: true,
            isCommitting: false,
            isGenerating: false
        )

        XCTAssertFalse(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertTrue(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Sync")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionDoesNotEnableSyncWhileCommitMessageExists() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: true,
            hasSyncWork: true,
            isCommitting: false,
            isGenerating: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertTrue(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionEnablesSyncWhenRemoteIsAheadWithoutLocalCommits() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: false,
            hasSyncWork: true,
            isCommitting: false,
            isGenerating: false
        )

        XCTAssertFalse(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertTrue(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Sync")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }
}
