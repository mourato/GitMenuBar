import AppKit
@testable import GitMenuBar
import XCTest

final class DirectoryPickerServiceTests: XCTestCase {
    func testConfigurePanelShowsHiddenDirectoriesAndPreservesDirectorySelectionDefaults() {
        let panel = NSOpenPanel()

        DirectoryPickerService().configurePanel(
            panel,
            title: "Select Project",
            prompt: "Choose"
        )

        XCTAssertTrue(panel.showsHiddenFiles)
        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertTrue(panel.canCreateDirectories)
        XCTAssertEqual(panel.title, "Select Project")
        XCTAssertEqual(panel.prompt, "Choose")
        XCTAssertFalse(panel.worksWhenModal)
    }

    func testConfigurePanelCannotDisableHiddenDirectoriesThroughPreparationHook() {
        let panel = NSOpenPanel()

        DirectoryPickerService().configurePanel(
            panel,
            title: "Select Project",
            prompt: "Choose",
            preparePanel: { panel in
                panel.showsHiddenFiles = false
            }
        )

        XCTAssertTrue(panel.showsHiddenFiles)
    }
}
