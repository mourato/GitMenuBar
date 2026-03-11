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
            syncLabelState: .pushOnly,
            canAutoCommit: true,
            isBusy: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertTrue(state.canCommit)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertEqual(state.primaryButtonSystemImage, "checkmark")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionKeepsCommitDisabledWhenMessageIsMissing() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            hasCommitMessage: false,
            syncLabelState: .pushOnly,
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertEqual(state.primaryButtonSystemImage, "checkmark")
        XCTAssertTrue(state.isPrimaryButtonDisabled)
        XCTAssertFalse(state.showsIdleCommitState)
    }

    func testPrimaryActionEnablesCommitWhenAutoCommitIsAvailable() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            hasCommitMessage: false,
            syncLabelState: .pushOnly,
            canAutoCommit: true,
            isBusy: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertTrue(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertEqual(state.primaryButtonSystemImage, "checkmark")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionShowsPushChangesWhenOnlyLocalCommitsNeedSync() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: false,
            syncLabelState: .pushOnly,
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertFalse(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertTrue(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Push Changes")
        XCTAssertEqual(state.primaryButtonSystemImage, "arrow.up")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionUsesSyncChangesWhenRemoteHasCommitsMissingLocally() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: true,
            syncLabelState: .syncChanges,
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertFalse(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertTrue(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Sync Changes")
        XCTAssertEqual(state.primaryButtonSystemImage, "arrow.2.circlepath")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionUsesSyncChangesWhenLocalAndRemoteAreDiverged() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: false,
            syncLabelState: .syncChanges,
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertFalse(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertTrue(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Sync Changes")
        XCTAssertEqual(state.primaryButtonSystemImage, "arrow.2.circlepath")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionFallsBackToDisabledCommitWhenNothingNeedsAction() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            hasCommitMessage: false,
            syncLabelState: .none,
            canAutoCommit: false,
            isBusy: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertFalse(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Nothing to commit")
        XCTAssertNil(state.primaryButtonSystemImage)
        XCTAssertTrue(state.isPrimaryButtonDisabled)
        XCTAssertTrue(state.showsIdleCommitState)
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
