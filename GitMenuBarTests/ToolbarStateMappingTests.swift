@testable import GitMenuBar
import XCTest

extension ToolbarStateMappingTests {
    // MARK: - Contextual Commit Item Visibility (State Model)

    func testShowsCommitItemWhenWorkingTreeIsClosedAndChangesExist() {
        let state = makeContextualToolbarState(changeCount: 3, isWorkingTreeOpen: false)

        XCTAssertTrue(state.showsCommitItem)
        XCTAssertTrue(state.repositoryItems.contains(.commit))
        XCTAssertEqual(state.commitItemTitle, "Commit (3)")
        XCTAssertTrue(state.isCommitEnabled)
    }

    func testHidesCommitItemWhenWorkingTreeIsOpenRegardlessOfChanges() {
        let stateWithChanges = makeContextualToolbarState(changeCount: 4, isWorkingTreeOpen: true)

        XCTAssertFalse(stateWithChanges.showsCommitItem)
        XCTAssertFalse(stateWithChanges.repositoryItems.contains(.commit))

        let stateBusyCommit = makeContextualToolbarState(
            changeCount: 0,
            isBusy: true,
            busyItem: .commit,
            isWorkingTreeOpen: true
        )

        XCTAssertFalse(stateBusyCommit.showsCommitItem)
        XCTAssertFalse(stateBusyCommit.repositoryItems.contains(.commit))
    }

    func testRestoresCommitItemWhenWorkingTreeCloses() {
        let openState = makeContextualToolbarState(changeCount: 2, isWorkingTreeOpen: true)
        XCTAssertFalse(openState.showsCommitItem)
        XCTAssertFalse(openState.repositoryItems.contains(.commit))

        let closedState = makeContextualToolbarState(changeCount: 2, isWorkingTreeOpen: false)
        XCTAssertTrue(closedState.showsCommitItem)
        XCTAssertTrue(closedState.repositoryItems.contains(.commit))
        XCTAssertEqual(closedState.commitItemTitle, "Commit (2)")
    }

    func testCommitItemPreservedWhenOtherSidePanelsAreOpen() {
        // When another side panel (such as branches, commit details, or stashes) is open,
        // isWorkingTreeOpen is false. The commit item remains visible if changes exist.
        let state = makeContextualToolbarState(changeCount: 1, isWorkingTreeOpen: false)

        XCTAssertTrue(state.showsCommitItem)
        XCTAssertTrue(state.repositoryItems.contains(.commit))
        XCTAssertEqual(state.commitItemTitle, "Commit (1)")
        XCTAssertEqual(state.commitAccessibilityLabel, "Commit 1 file in TestRepo")
    }

    func testShowsCommitItemWhenBusyWithCommitEvenWithZeroChanges() {
        let state = makeContextualToolbarState(
            changeCount: 0,
            isBusy: true,
            busyItem: .commit,
            isWorkingTreeOpen: false
        )

        XCTAssertTrue(state.showsCommitItem)
        XCTAssertTrue(state.repositoryItems.contains(.commit))
        XCTAssertEqual(state.commitItemTitle, "Commit")
        XCTAssertFalse(state.isCommitEnabled) // Disabled while busy
    }

    func testHidesCommitItemWhenNoChangesAndNotBusy() {
        let state = makeContextualToolbarState(changeCount: 0, isWorkingTreeOpen: false)

        XCTAssertFalse(state.showsCommitItem)
        XCTAssertFalse(state.repositoryItems.contains(.commit))
        XCTAssertEqual(state.commitItemTitle, "Commit")
        XCTAssertFalse(state.isCommitEnabled)
    }

    // MARK: - Neutral Count Formatting Contract

    func testNeutralCountItemTitleContract() {
        let zeroState = makeContextualToolbarState(changeCount: 0)
        XCTAssertEqual(zeroState.commitItemTitle, "Commit")
        XCTAssertEqual(zeroState.commitTitle, "Commit")

        let singleState = makeContextualToolbarState(changeCount: 1)
        XCTAssertEqual(singleState.commitItemTitle, "Commit (1)")
        XCTAssertEqual(singleState.commitTitle, "Commit")

        let multipleState = makeContextualToolbarState(changeCount: 5)
        XCTAssertEqual(multipleState.commitItemTitle, "Commit (5)")
        XCTAssertEqual(multipleState.commitTitle, "Commit")
        XCTAssertEqual(multipleState.commitAccessibilityLabel, "Commit 5 files in TestRepo")
    }

    // MARK: - Commit Count Matches the Next Commit

    func testCommitTitleCountsOnlyStagedFilesWhenSomeAreStaged() {
        // Two staged and two unstaged files: the next commit includes the staged two.
        let state = makeContextualToolbarState(changeCount: 4, commitFileCount: 2)

        XCTAssertEqual(state.commitItemTitle, "Commit (2)")
        XCTAssertEqual(state.commitAccessibilityLabel, "Commit 2 files in TestRepo")
        XCTAssertTrue(state.showsCommitItem)
    }

    @MainActor
    func testGitManagerCommitFileCountMatchesWorkingTreeCommitRule() {
        let gitManager = GitManager(repositoryPathOverride: "")
        gitManager.stagedFiles = []
        gitManager.changedFiles = [
            WorkingTreeFile(path: "A.swift", lineDiff: .zero, status: .modified),
            WorkingTreeFile(path: "B.swift", lineDiff: .zero, status: .untracked),
            WorkingTreeFile(path: "C.swift", lineDiff: .zero, status: .modified)
        ]
        XCTAssertEqual(gitManager.commitFileCount, 3)

        gitManager.stagedFiles = [WorkingTreeFile(path: "A.swift", lineDiff: .zero, status: .modified)]
        XCTAssertEqual(gitManager.commitFileCount, 1)
    }

    // MARK: - Helper

    private func makeContextualToolbarState(
        repositoryName: String = "TestRepo",
        branchName: String = "main",
        aheadCount: Int = 0,
        behindCount: Int = 0,
        changeCount: Int = 0,
        commitFileCount: Int? = nil,
        isBusy: Bool = false,
        busyItem: MainWindowToolbarRepositoryItem? = nil,
        progressAccessibilityLabel: String? = nil,
        isWorkingTreeOpen: Bool = false
    ) -> MainWindowToolbarRepositoryState {
        MainWindowToolbarRepositoryState(
            repositoryName: repositoryName,
            branchName: branchName,
            aheadCount: aheadCount,
            behindCount: behindCount,
            changeCount: changeCount,
            commitFileCount: commitFileCount ?? changeCount,
            isBusy: isBusy,
            busyItem: busyItem,
            progressAccessibilityLabel: progressAccessibilityLabel,
            isWorkingTreeOpen: isWorkingTreeOpen
        )
    }
}
