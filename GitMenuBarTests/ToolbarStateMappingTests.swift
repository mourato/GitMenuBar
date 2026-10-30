@testable import GitMenuBar
import XCTest

extension ToolbarStateMappingTests {
    // MARK: - Contextual Commit Item Visibility (State Model)

    func testShowsCommitItemWhenWorkingTreeIsClosedAndChangesExist() {
        let state = makeContextualToolbarState(changeCount: 3, isWorkingTreeOpen: false)

        XCTAssertTrue(state.showsCommitItem)
        XCTAssertTrue(state.repositoryItems.contains(.commit))
        XCTAssertEqual(state.commitBadgeCount, 3)
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
        XCTAssertEqual(closedState.commitBadgeCount, 2)
        XCTAssertEqual(closedState.commitItemTitle, "Commit (2)")
    }

    func testCommitItemPreservedWhenOtherSidePanelsAreOpen() {
        // When another side panel (such as branches, commit details, or stashes) is open,
        // isWorkingTreeOpen is false. The commit item remains visible if changes exist.
        let state = makeContextualToolbarState(changeCount: 1, isWorkingTreeOpen: false)

        XCTAssertTrue(state.showsCommitItem)
        XCTAssertTrue(state.repositoryItems.contains(.commit))
        XCTAssertEqual(state.commitBadgeCount, 1)
        XCTAssertEqual(state.commitItemTitle, "Commit (1)")
        XCTAssertEqual(state.commitAccessibilityLabel, "Commit 1 change in TestRepo")
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
        XCTAssertNil(state.commitBadgeCount)
        XCTAssertEqual(state.commitItemTitle, "Commit")
        XCTAssertFalse(state.isCommitEnabled) // Disabled while busy
    }

    func testHidesCommitItemWhenNoChangesAndNotBusy() {
        let state = makeContextualToolbarState(changeCount: 0, isWorkingTreeOpen: false)

        XCTAssertFalse(state.showsCommitItem)
        XCTAssertFalse(state.repositoryItems.contains(.commit))
        XCTAssertNil(state.commitBadgeCount)
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
        XCTAssertEqual(multipleState.commitAccessibilityLabel, "Commit 5 changes in TestRepo")
    }

    // MARK: - Isolated Seam Tests: MainWindowToolbarWorkspaceObserver

    @MainActor
    func testNotificationConsumedBeforeAnyPropertyRead() {
        let notificationCenter = NotificationCenter()
        var refreshCount = 0
        let observer = MainWindowToolbarWorkspaceObserver(
            notificationCenter: notificationCenter,
            onRefresh: { refreshCount += 1 }
        )
        let workspace = MainMenuWorkspaceState()

        // Post bind notification BEFORE reading any property on observer
        notificationCenter.post(name: .mainMenuWorkspaceDidBind, object: workspace)

        // Now query properties: observer must have already consumed the notification (D1 fix)
        XCTAssertTrue(observer.workspace === workspace)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertFalse(observer.isWorkingTreeOpen(route: .main))
    }

    @MainActor
    func testWorkspaceBindingAndSelectionRefresh() async {
        var currentExpectation: XCTestExpectation?
        var refreshCount = 0
        let notificationCenter = NotificationCenter()
        let observer = MainWindowToolbarWorkspaceObserver(
            notificationCenter: notificationCenter,
            onRefresh: {
                refreshCount += 1
                currentExpectation?.fulfill()
                currentExpectation = nil
            }
        )
        let workspace = MainMenuWorkspaceState()

        // 1. Initial state
        XCTAssertNil(observer.workspace)
        XCTAssertFalse(observer.isWorkingTreeOpen(route: .main))
        XCTAssertEqual(refreshCount, 0)

        // 2. Bind workspace (synchronous refresh)
        observer.bindWorkspace(workspace)
        XCTAssertTrue(observer.workspace === workspace)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertFalse(observer.isWorkingTreeOpen(route: .main))

        // 3. Select working tree: triggers observation change and executes onRefresh on MainActor
        let expectWorkingTree = XCTestExpectation(description: "refresh after selecting workingTree")
        currentExpectation = expectWorkingTree
        workspace.selectedSidePanelSelection = .workingTree
        await fulfillment(of: [expectWorkingTree], timeout: 2.0)
        XCTAssertEqual(refreshCount, 2)
        XCTAssertTrue(observer.isWorkingTreeOpen(route: .main))

        // Route independence: route away from main returns false without breaking selection
        XCTAssertFalse(observer.isWorkingTreeOpen(route: .createRepo(path: "/tmp/repo")))
        XCTAssertTrue(observer.isWorkingTreeOpen(route: .main))

        // 4. Switch to branches: contextual selection is no longer working tree
        let expectBranches = XCTestExpectation(description: "refresh after selecting branches")
        currentExpectation = expectBranches
        workspace.selectedSidePanelSelection = .branches
        await fulfillment(of: [expectBranches], timeout: 2.0)
        XCTAssertEqual(refreshCount, 3)
        XCTAssertFalse(observer.isWorkingTreeOpen(route: .main))

        // 5. Clear selection
        let expectClear = XCTestExpectation(description: "refresh after clearing selection")
        currentExpectation = expectClear
        workspace.clearSidePanelSelection()
        await fulfillment(of: [expectClear], timeout: 2.0)
        XCTAssertEqual(refreshCount, 4)
        XCTAssertFalse(observer.isWorkingTreeOpen(route: .main))
    }

    @MainActor
    func testNotificationCenterBindingLifecycleAndOldUnbindIgnored() {
        var refreshCount = 0
        let notificationCenter = NotificationCenter()
        let observer = MainWindowToolbarWorkspaceObserver(
            notificationCenter: notificationCenter,
            onRefresh: { refreshCount += 1 }
        )

        let workspaceA = MainMenuWorkspaceState()
        let workspaceB = MainMenuWorkspaceState()

        // 1. Bind workspaceA via notification
        notificationCenter.post(name: .mainMenuWorkspaceDidBind, object: workspaceA)
        XCTAssertTrue(observer.workspace === workspaceA)
        XCTAssertEqual(refreshCount, 1)

        // 2. Bind workspaceB (simulating new view appeared before old unbind)
        notificationCenter.post(name: .mainMenuWorkspaceDidBind, object: workspaceB)
        XCTAssertTrue(observer.workspace === workspaceB)
        XCTAssertEqual(refreshCount, 2)

        // 3. Delayed unbind notification from old workspaceA MUST NOT unbind workspaceB (N1 fix)
        notificationCenter.post(name: .mainMenuWorkspaceDidUnbind, object: workspaceA)
        XCTAssertTrue(observer.workspace === workspaceB)
        XCTAssertEqual(refreshCount, 2)

        // 4. Unbind notification matching currently active workspaceB successfully unbinds
        notificationCenter.post(name: .mainMenuWorkspaceDidUnbind, object: workspaceB)
        XCTAssertNil(observer.workspace)
        XCTAssertEqual(refreshCount, 3)
    }

    @MainActor
    func testRepeatedBindOfSameWorkspaceIsIdempotent() {
        var refreshCount = 0
        let observer = MainWindowToolbarWorkspaceObserver(onRefresh: { refreshCount += 1 })
        let workspace = MainMenuWorkspaceState()

        observer.bindWorkspace(workspace)
        XCTAssertEqual(refreshCount, 1)

        // Subsequent binds of the identical instance are no-ops (N2 fix)
        observer.bindWorkspace(workspace)
        XCTAssertEqual(refreshCount, 1)
        observer.bindWorkspace(workspace)
        XCTAssertEqual(refreshCount, 1)
    }

    @MainActor
    func testRebindSameWorkspaceInvalidatesStaleObservationTask() async {
        var currentExpectation: XCTestExpectation?
        var refreshCount = 0
        let observer = MainWindowToolbarWorkspaceObserver(onRefresh: {
            refreshCount += 1
            currentExpectation?.fulfill()
            currentExpectation = nil
        })
        let workspace = MainMenuWorkspaceState()

        // Bind first generation (synchronous)
        observer.bindWorkspace(workspace)
        XCTAssertEqual(refreshCount, 1)

        // Mutate selection and unbind immediately
        workspace.selectedSidePanelSelection = .workingTree
        observer.unbindWorkspace(workspace)
        XCTAssertEqual(refreshCount, 2)
        XCTAssertNil(observer.workspace)

        // Rebind same workspace instance (starts fresh generation, synchronous)
        observer.bindWorkspace(workspace)
        XCTAssertEqual(refreshCount, 3)
        XCTAssertTrue(observer.workspace === workspace)

        // Mutate again under new generation: triggers async observation for generation 3
        let expectBranches = XCTestExpectation(description: "refresh for re-bound workspace")
        currentExpectation = expectBranches
        workspace.selectedSidePanelSelection = .branches
        await fulfillment(of: [expectBranches], timeout: 2.0)

        // Count must be exactly 4 (no duplicate refreshes from prior generation)
        XCTAssertEqual(refreshCount, 4)
        XCTAssertFalse(observer.isWorkingTreeOpen(route: .main))
    }

    @MainActor
    func testWeakWorkspaceDeallocation() {
        var refreshCount = 0
        let observer = MainWindowToolbarWorkspaceObserver(onRefresh: { refreshCount += 1 })

        var scopedWorkspace: MainMenuWorkspaceState? = MainMenuWorkspaceState()
        observer.bindWorkspace(scopedWorkspace)
        XCTAssertNotNil(observer.workspace)
        XCTAssertEqual(refreshCount, 1)

        scopedWorkspace = nil
        XCTAssertNil(observer.workspace)
        XCTAssertFalse(observer.isWorkingTreeOpen(route: .main))
    }

    // MARK: - Helper

    private func makeContextualToolbarState(
        repositoryName: String = "TestRepo",
        branchName: String = "main",
        aheadCount: Int = 0,
        behindCount: Int = 0,
        changeCount: Int = 0,
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
            isBusy: isBusy,
            busyItem: busyItem,
            progressAccessibilityLabel: progressAccessibilityLabel,
            isWorkingTreeOpen: isWorkingTreeOpen
        )
    }
}
