@testable import GitMenuBar
import XCTest

@MainActor
final class MainMenuWorkspaceStateTests: XCTestCase {
    func testWorkingTreePanelStaysOpenWhenSelectableItemsChange() {
        let workspace = MainMenuWorkspaceState()
        workspace.selectedSidePanelSelection = .workingTree

        workspace.synchronizeSelectedMainItem(with: [.stagedFile(path: "README.md")])

        XCTAssertEqual(workspace.selectedSidePanelSelection, .workingTree)
    }

    func testWorkingTreePanelStaysOpenWhenSelectedFileMovesSections() {
        let workspace = MainMenuWorkspaceState()
        workspace.selectedMainItemID = .unstagedFile(path: "README.md")
        workspace.selectedSidePanelSelection = .workingTree

        workspace.synchronizeSelectedMainItem(with: [.stagedFile(path: "README.md")])

        XCTAssertNil(workspace.selectedMainItemID)
        XCTAssertEqual(workspace.selectedSidePanelSelection, .workingTree)
    }

    func testFilePanelFallsBackToWorkingTreeWhenItsFileLeavesTheList() {
        let workspace = MainMenuWorkspaceState()
        workspace.selectMainItem(.unstagedFile(path: "README.md"))

        workspace.synchronizeSelectedMainItem(with: [.stagedFile(path: "README.md")])

        XCTAssertNil(workspace.selectedMainItemID)
        XCTAssertEqual(workspace.selectedSidePanelSelection, .workingTree)
    }

    func testCommitPanelFallsBackToHistoryWhenItsCommitLeavesTheList() {
        let workspace = MainMenuWorkspaceState()
        workspace.selectMainItem(.historyCommit(id: "abc"))

        workspace.synchronizeSelectedMainItem(with: [])

        XCTAssertEqual(workspace.selectedSidePanelSelection, .history)
    }

    func testSelectingWorkspaceFileKeepsWorkingTreePanelThroughDiscard() {
        let workspace = MainMenuWorkspaceState()
        workspace.selectedSidePanelSelection = .workingTree
        workspace.selectWorkspaceFile(.unstagedFile(path: "README.md"))

        XCTAssertEqual(workspace.selectedSidePanelSelection, .workingTree)

        workspace.synchronizeSelectedMainItem(with: [])

        XCTAssertNil(workspace.selectedMainItemID)
        XCTAssertEqual(workspace.selectedSidePanelSelection, .workingTree)
    }

    func testMovingSelectionInEmptyListKeepsPanelOpen() {
        let workspace = MainMenuWorkspaceState()
        workspace.selectedSidePanelSelection = .workingTree

        workspace.moveMainSelection(.down, in: [])

        XCTAssertEqual(workspace.selectedSidePanelSelection, .workingTree)
    }
}
