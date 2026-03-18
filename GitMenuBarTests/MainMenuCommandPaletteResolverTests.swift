@testable import GitMenuBar
import XCTest

final class MainMenuCommandPaletteResolverTests: XCTestCase {
    func testResolveItemsMirrorsDynamicGitActions() {
        let actionState = StatusBarContextMenuActionState.resolve(
            hasCommitWork: true,
            hasSyncWork: true,
            canAutoCommit: false,
            canSync: true
        )

        let items = MainMenuCommandPaletteResolver.resolveItems(
            actionState: actionState,
            syncActionTitle: "Sync Changes",
            recentPaths: [],
            currentRepoPath: ""
        )

        XCTAssertEqual(
            items.filter { $0.section == .actions }.map(\.title),
            ["Commit", "Commit & Push", "Sync Changes"]
        )

        let commitItem = items.first(where: { $0.kind == .commit })
        XCTAssertEqual(commitItem?.isEnabled, false)

        let syncItem = items.first(where: { $0.kind == .sync })
        XCTAssertEqual(syncItem?.isEnabled, true)
    }

    func testResolveItemsExcludesCurrentRepoAndLimitsRecentProjectsToFive() {
        let actionState = StatusBarContextMenuActionState.resolve(
            hasCommitWork: false,
            hasSyncWork: false,
            canAutoCommit: false,
            canSync: false
        )

        let recents = [
            "/tmp/current",
            "/tmp/a",
            "/tmp/b",
            "/tmp/c",
            "/tmp/d",
            "/tmp/e",
            "/tmp/f"
        ]

        let items = MainMenuCommandPaletteResolver.resolveItems(
            actionState: actionState,
            syncActionTitle: "Sync Changes",
            recentPaths: recents,
            currentRepoPath: "/tmp/current"
        )

        let recentProjectItems = items.filter { $0.section == .recentProjects }

        XCTAssertEqual(recentProjectItems.count, 5)
        XCTAssertEqual(
            recentProjectItems.map(\.kind),
            [
                .recentProject(path: "/tmp/a"),
                .recentProject(path: "/tmp/b"),
                .recentProject(path: "/tmp/c"),
                .recentProject(path: "/tmp/d"),
                .recentProject(path: "/tmp/e")
            ]
        )
    }

    func testFilteredItemsMatchesQueryCaseInsensitively() {
        let items = [
            MainMenuCommandPaletteItem(
                kind: .commit,
                section: .actions,
                title: "Commit",
                subtitle: "Generate commit message",
                keywords: ["git", "working tree"],
                isEnabled: true
            ),
            MainMenuCommandPaletteItem(
                kind: .quitApp,
                section: .app,
                title: "Quit App",
                subtitle: "Close GitMenuBar",
                keywords: ["exit"],
                isEnabled: true
            )
        ]

        let filtered = MainMenuCommandPaletteResolver.filteredItems(from: items, query: "WoRkInG")

        XCTAssertEqual(filtered.map(\.title), ["Commit"])
    }

    func testDefaultSelectionPicksFirstExecutableItem() {
        let items = [
            MainMenuCommandPaletteItem(
                kind: .commit,
                section: .actions,
                title: "Commit",
                subtitle: nil,
                keywords: [],
                isEnabled: false
            ),
            MainMenuCommandPaletteItem(
                kind: .sync,
                section: .actions,
                title: "Sync Changes",
                subtitle: nil,
                keywords: [],
                isEnabled: true
            )
        ]

        let selectedID = MainMenuCommandPaletteResolver.defaultSelectionID(for: items)

        XCTAssertEqual(selectedID, MainMenuCommandPaletteKind.sync.stableID)
    }

    func testExecutionDecisionRequiresConfirmationForRestart() {
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .restartApp),
            .requiresConfirmation
        )
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .quitApp),
            .executeNow
        )
    }
}
