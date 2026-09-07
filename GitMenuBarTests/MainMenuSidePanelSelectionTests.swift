@testable import GitMenuBar
import XCTest

final class MainMenuSidePanelSelectionTests: XCTestCase {
    func testStableIDsCoverEverySelectionCase() {
        let selections: [MainMenuSidePanelSelection] = [
            .workingTree, .branches, .unpushedCommits, .stashes, .history,
            .stagedFile(path: "Sources/App.swift"),
            .unstagedFile(path: "Sources/Other.swift"),
            .branch(name: "feature/inspector"),
            .stash(id: "stash-hash"), .commit(id: "commit-hash")
        ]

        XCTAssertEqual(selections.map(\.id), [
            "working-tree", "branches", "unpushed-commits", "stashes", "history",
            "staged-file:Sources/App.swift", "unstaged-file:Sources/Other.swift",
            "branch:feature/inspector", "stash:stash-hash", "commit:commit-hash"
        ])
    }

    func testMainMenuItemsMapToSidePanelSelections() {
        XCTAssertEqual(
            MainMenuSidePanelSelection(mainMenuItem: .stagedFile(path: "a.txt")),
            .stagedFile(path: "a.txt")
        )
        XCTAssertEqual(
            MainMenuSidePanelSelection(mainMenuItem: .unstagedFile(path: "b.txt")),
            .unstagedFile(path: "b.txt")
        )
        XCTAssertEqual(
            MainMenuSidePanelSelection(mainMenuItem: .historyCommit(id: "abc123")),
            .commit(id: "abc123")
        )
    }

    func testSidePanelDefaultsToLargestWorkbenchColumn() {
        XCTAssertGreaterThan(
            WorkbenchMetrics.sidePanelWidth,
            WorkbenchMetrics.centralMinimumWidth
        )
        XCTAssertEqual(
            WorkbenchMetrics.mainWindowInitialWidth,
            WorkbenchMetrics.projectsMinimumWidth
                + WorkbenchMetrics.centralMinimumWidth
                + WorkbenchMetrics.sidePanelWidth
                + (WorkbenchMetrics.windowPadding * 2)
                + WorkbenchMetrics.splitDividerThickness
        )
    }

    func testMainWindowMinimumIsTwoColumnFloor() {
        XCTAssertEqual(
            WorkbenchMetrics.mainWindowMinimumWidth,
            WorkbenchMetrics.projectsMinimumWidth
                + WorkbenchMetrics.centralMinimumWidth
                + (WorkbenchMetrics.windowPadding * 2)
                + WorkbenchMetrics.splitDividerThickness
        )
        XCTAssertGreaterThan(
            WorkbenchMetrics.projectsMaximumWidth,
            WorkbenchMetrics.projectsMinimumWidth
        )
    }

    func testLegacyInspectorColumnWidthKeyRemainsReadable() throws {
        let suiteName = "MainMenuSidePanelSelectionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(864.0, forKey: AppPreferences.Keys.inspectorColumnWidth)

        XCTAssertEqual(defaults.double(forKey: AppPreferences.Keys.inspectorColumnWidth), 864.0)
    }
}
