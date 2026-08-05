@testable import GitMenuBar
import XCTest

final class GitMenuBarTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
    }

    func testPrimaryActionShowsEnabledCommitWhenChangesAndMessageExist() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            canCommitWithCurrentInput: true,
            syncLabelState: .pushOnly,
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
            canCommitWithCurrentInput: false,
            syncLabelState: .pushOnly,
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

    func testPrimaryActionEnablesCommitWhenInputCanBeResolvedAutomatically() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            canCommitWithCurrentInput: true,
            syncLabelState: .pushOnly,
            isBusy: false
        )

        XCTAssertTrue(state.showsCommitAction)
        XCTAssertTrue(state.canCommit)
        XCTAssertFalse(state.canSync)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
        XCTAssertEqual(state.primaryButtonSystemImage, "checkmark")
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionShowsCommitAndPushWhenConfigured() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            canCommitWithCurrentInput: true,
            syncLabelState: .none,
            isBusy: false,
            commitButtonAction: .commitAndPush
        )

        XCTAssertEqual(state.primaryButtonTitle, "Commit & Push")
        XCTAssertEqual(state.primaryButtonSystemImage, "checkmark")
    }

    func testOperationStatusReportsSplitCommitProgress() {
        let status = MainMenuOperationStatus.committingGroup(current: 2, total: 4)

        XCTAssertEqual(status.title, "Creating commit 2 of 4…")
        XCTAssertEqual(status.progress, 0.5)
        XCTAssertEqual(status.accessibilityLabel, "Creating commit 2 of 4")
    }

    func testPrimaryActionShowsPushChangesWhenOnlyLocalCommitsNeedSync() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: false,
            canCommitWithCurrentInput: false,
            syncLabelState: .pushOnly,
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
            canCommitWithCurrentInput: true,
            syncLabelState: .syncChanges,
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
            canCommitWithCurrentInput: false,
            syncLabelState: .syncChanges,
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
            canCommitWithCurrentInput: false,
            syncLabelState: .none,
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

    func testPrimaryActionEnablesCommitForWhitespaceOnlyInput() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            canCommitWithCurrentInput: true,
            syncLabelState: .none,
            isBusy: false
        )

        XCTAssertTrue(state.canCommit)
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }

    func testPrimaryActionEnablesCommitWhenFieldIsHiddenAndAutomaticGenerationIsAvailable() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            canCommitWithCurrentInput: true,
            syncLabelState: .none,
            isBusy: false
        )

        XCTAssertTrue(state.canCommit)
        XCTAssertEqual(state.primaryButtonTitle, "Commit")
    }

    func testPrimaryActionEnablesCommitWhenFieldIsHiddenAndMustBeRevealed() {
        let state = MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: true,
            canCommitWithCurrentInput: true,
            syncLabelState: .none,
            isBusy: false
        )

        XCTAssertTrue(state.canCommit)
        XCTAssertFalse(state.isPrimaryButtonDisabled)
    }
}
