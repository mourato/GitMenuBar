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
            currentRepoPath: "",
            currentBranch: "main",
            canDoAtomicCommits: false,
            isBehindRemote: false,
            isAheadOfRemote: false,
            canShowBranchManagement: false,
            defaultBranchName: "main"
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
            currentRepoPath: "/tmp/current",
            currentBranch: "main",
            canDoAtomicCommits: false,
            isBehindRemote: false,
            isAheadOfRemote: false,
            canShowBranchManagement: false,
            defaultBranchName: "main"
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

    func testResolveItemsIncludesAtomicCommitsWhenAvailable() {
        let actionState = StatusBarContextMenuActionState.resolve(
            hasCommitWork: false, hasSyncWork: false, canAutoCommit: false, canSync: false
        )

        let items = MainMenuCommandPaletteResolver.resolveItems(
            actionState: actionState,
            syncActionTitle: "",
            recentPaths: [],
            currentRepoPath: "/tmp/repo",
            currentBranch: "main",
            canDoAtomicCommits: true,
            isBehindRemote: false,
            isAheadOfRemote: false,
            canShowBranchManagement: true,
            defaultBranchName: "main"
        )

        XCTAssertNotNil(items.first(where: { $0.kind == .atomicCommits }))
        XCTAssertNotNil(items.first(where: { $0.kind == .branchManagement }))
        XCTAssertNotNil(items.first(where: { $0.kind == .createBranch }))
        XCTAssertNotNil(items.first(where: { $0.kind == .switchToBranchList }))
    }

    func testResolveItemsShowsMergeToDefaultOnlyWhenOffDefaultBranch() {
        let actionState = StatusBarContextMenuActionState.resolve(
            hasCommitWork: false, hasSyncWork: false, canAutoCommit: false, canSync: false
        )

        let itemsOnFeature = MainMenuCommandPaletteResolver.resolveItems(
            actionState: actionState,
            syncActionTitle: "",
            recentPaths: [],
            currentRepoPath: "/tmp/repo",
            currentBranch: "feature",
            canDoAtomicCommits: false,
            isBehindRemote: false,
            isAheadOfRemote: false,
            canShowBranchManagement: true,
            defaultBranchName: "main"
        )

        XCTAssertNotNil(itemsOnFeature.first(where: {
            if case .mergeToDefault = $0.kind { return true }
            return false
        }))

        let itemsOnMain = MainMenuCommandPaletteResolver.resolveItems(
            actionState: actionState,
            syncActionTitle: "",
            recentPaths: [],
            currentRepoPath: "/tmp/repo",
            currentBranch: "main",
            canDoAtomicCommits: false,
            isBehindRemote: false,
            isAheadOfRemote: false,
            canShowBranchManagement: true,
            defaultBranchName: "main"
        )

        XCTAssertNil(itemsOnMain.first {
            if case .mergeToDefault = $0.kind { return true }
            return false
        })
    }

    func testResolveItemsIncludesPushAndPullBasedOnRemoteState() {
        let actionState = StatusBarContextMenuActionState.resolve(
            hasCommitWork: false, hasSyncWork: false, canAutoCommit: false, canSync: false
        )

        let itemsAhead = MainMenuCommandPaletteResolver.resolveItems(
            actionState: actionState,
            syncActionTitle: "",
            recentPaths: [],
            currentRepoPath: "/tmp/repo",
            currentBranch: "main",
            canDoAtomicCommits: false,
            isBehindRemote: false,
            isAheadOfRemote: true,
            canShowBranchManagement: true,
            defaultBranchName: "main"
        )

        XCTAssertNotNil(itemsAhead.first(where: { $0.kind == .push }))
        XCTAssertNil(itemsAhead.first(where: { $0.kind == .pull }))

        let itemsBehind = MainMenuCommandPaletteResolver.resolveItems(
            actionState: actionState,
            syncActionTitle: "",
            recentPaths: [],
            currentRepoPath: "/tmp/repo",
            currentBranch: "main",
            canDoAtomicCommits: false,
            isBehindRemote: true,
            isAheadOfRemote: false,
            canShowBranchManagement: true,
            defaultBranchName: "main"
        )

        XCTAssertNil(itemsBehind.first(where: { $0.kind == .push }))
        XCTAssertNotNil(itemsBehind.first(where: { $0.kind == .pull }))
    }

    func testResolveItemsBranchesSection() {
        let actionState = StatusBarContextMenuActionState.resolve(
            hasCommitWork: false, hasSyncWork: false, canAutoCommit: false, canSync: false
        )

        let items = MainMenuCommandPaletteResolver.resolveItems(
            actionState: actionState,
            syncActionTitle: "",
            recentPaths: [],
            currentRepoPath: "/tmp/repo",
            currentBranch: "main",
            canDoAtomicCommits: false,
            isBehindRemote: false,
            isAheadOfRemote: false,
            canShowBranchManagement: true,
            defaultBranchName: "main"
        )

        let branchItems = items.filter { $0.section == .branches }
        XCTAssertFalse(branchItems.isEmpty)
        XCTAssertTrue(branchItems.allSatisfy { $0.section == .branches })
    }

    func testExecutionDecisionForNewKinds() {
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .atomicCommits),
            .executeNow
        )
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .branchManagement),
            .executeNow
        )
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .createBranch),
            .executeNow
        )
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .mergeToDefault(featureBranch: "test")),
            .executeNow
        )
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .push),
            .executeNow
        )
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .pull),
            .executeNow
        )
        XCTAssertEqual(
            MainMenuCommandPaletteResolver.executionDecision(for: .switchToBranchList),
            .executeNow
        )
    }
}
