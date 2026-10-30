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

    func testFilePanelClosesWhenItsFileLeavesTheList() {
        let workspace = MainMenuWorkspaceState()
        workspace.selectMainItem(.unstagedFile(path: "README.md"))

        workspace.synchronizeSelectedMainItem(with: [.stagedFile(path: "README.md")])

        XCTAssertNil(workspace.selectedMainItemID)
        XCTAssertNil(workspace.selectedSidePanelSelection)
    }
}
