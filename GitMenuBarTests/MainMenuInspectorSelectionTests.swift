@testable import GitMenuBar
import XCTest

final class MainMenuInspectorSelectionTests: XCTestCase {
    func testStableIDsCoverEverySelectionCase() {
        let selections: [MainMenuInspectorSelection] = [
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

    func testMainMenuItemsMapToInspectorSelections() {
        XCTAssertEqual(
            MainMenuInspectorSelection(mainMenuItem: .stagedFile(path: "a.txt")),
            .stagedFile(path: "a.txt")
        )
        XCTAssertEqual(
            MainMenuInspectorSelection(mainMenuItem: .unstagedFile(path: "b.txt")),
            .unstagedFile(path: "b.txt")
        )
        XCTAssertEqual(
            MainMenuInspectorSelection(mainMenuItem: .historyCommit(id: "abc123")),
            .commit(id: "abc123")
        )
    }

    func testInspectorDefaultsToLargestWorkbenchColumn() {
        XCTAssertGreaterThan(
            WorkbenchMetrics.inspectorDefaultWidth,
            WorkbenchMetrics.centralMinimumWidth
        )
        XCTAssertEqual(
            WorkbenchMetrics.mainWindowInitialWidth,
            WorkbenchMetrics.projectsMinimumWidth
                + WorkbenchMetrics.centralMinimumWidth
                + WorkbenchMetrics.inspectorDefaultWidth
                + (WorkbenchMetrics.windowPadding * 2)
        )
    }

    func testInspectorColumnWidthPreferenceRoundTrips() throws {
        let suiteName = "MainMenuInspectorSelectionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(864.0, forKey: AppPreferences.Keys.inspectorColumnWidth)

        XCTAssertEqual(defaults.double(forKey: AppPreferences.Keys.inspectorColumnWidth), 864.0)
    }
}
