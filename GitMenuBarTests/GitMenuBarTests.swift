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
            canAutoCommit: true,
            isBusy: false
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
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertTrue(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionEnablesCommitWhenAutoCommitIsAvailable() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            hasCommitMessage: false,
            hasSyncWork: true,
            canAutoCommit: true,
            isBusy: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertTrue(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionEnablesSyncWhenAheadAndCommitInputsAreIdle() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: false,
            hasSyncWork: true,
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertFalse(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertTrue(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Sync Changes")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionIgnoresTypedMessageWhenThereAreNoWorkingTreeChanges() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: true,
            hasSyncWork: true,
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertFalse(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertTrue(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Sync Changes")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionFallsBackToDisabledCommitWhenNothingNeedsAction() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: false,
            hasSyncWork: false,
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertTrue(state.isPrimaryButtonDisabled)
    }

    func testContextMenuHidesCommitActionsWhenThereIsNothingToCommit() {
        let state = StatusBarContextMenuActionState.resolve(
            hasCommitWork: false,
            hasSyncWork: true,
            canAutoCommit: false,
            canSync: true
        )

        XCTAssertFalse(state.showsCommit)
        XCTAssertFalse(state.showsCommitAndPush)
        XCTAssertTrue(state.showsSync)
        XCTAssertTrue(state.canSync)
    }

    func testContextMenuHidesSyncWhenThereIsNothingToSynchronize() {
        let state = StatusBarContextMenuActionState.resolve(
            hasCommitWork: true,
            hasSyncWork: false,
            canAutoCommit: true,
            canSync: false
        )

        XCTAssertTrue(state.showsCommit)
        XCTAssertTrue(state.showsCommitAndPush)
        XCTAssertFalse(state.showsSync)
    }
}
