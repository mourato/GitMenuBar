@testable import GitMenuBar
import XCTest

final class AppCommandResolverTests: XCTestCase {
    func testResolveSnapshotReflectsRepositoryAndActionAvailability() {
        let actionState = StatusBarContextMenuActionState.resolve(
            hasCommitWork: true,
            hasSyncWork: true,
            canAutoCommit: false,
            canSync: true
        )

        let snapshot = AppCommandResolver.resolveSnapshot(
            context: AppCommandContext(
                actionState: actionState,
                syncActionTitle: "Sync Changes",
                currentRepoPath: "/tmp/current",
                remoteUrl: "git@github.com:saihgupr/GitMenuBar.git",
                recentPaths: [],
                isGitHubAuthenticated: true,
                hasWorkingTreeChanges: true,
                canDoAtomicCommits: false,
                isBehindRemote: false,
                isAheadOfRemote: true,
                canShowBranchManagement: true,
                currentBranch: "feature",
                defaultBranchName: "main"
            )
        )

        XCTAssertEqual(snapshot.states[AppCommandID.commit], AppCommandState(title: "Commit", isEnabled: false))
        XCTAssertEqual(snapshot.states[AppCommandID.sync], AppCommandState(title: "Sync Changes", isEnabled: true))
        XCTAssertEqual(
            snapshot.states[AppCommandID.showRepositoryOptions],
            AppCommandState(title: "Repository Options…", isEnabled: true)
        )
        XCTAssertEqual(
            snapshot.states[AppCommandID.revealRepositoryInFinder],
            AppCommandState(title: "Reveal in Finder", isEnabled: true)
        )
    }

    func testResolveSnapshotExcludesCurrentRepositoryAndLimitsRecents() {
        let snapshot = AppCommandResolver.resolveSnapshot(
            context: AppCommandContext(
                actionState: StatusBarContextMenuActionState.resolve(
                    hasCommitWork: false,
                    hasSyncWork: false,
                    canAutoCommit: false,
                    canSync: false
                ),
                syncActionTitle: "Sync Changes",
                currentRepoPath: "/tmp/current",
                remoteUrl: "",
                recentPaths: [
                    "/tmp/current",
                    "/tmp/a",
                    "/tmp/b",
                    "/tmp/c",
                    "/tmp/d",
                    "/tmp/e",
                    "/tmp/f"
                ],
                isGitHubAuthenticated: false,
                hasWorkingTreeChanges: false,
                canDoAtomicCommits: false,
                isBehindRemote: false,
                isAheadOfRemote: false,
                canShowBranchManagement: true,
                currentBranch: "main",
                defaultBranchName: "main"
            )
        )

        XCTAssertEqual(snapshot.recentProjects.count, 5)
        XCTAssertEqual(
            snapshot.recentProjects.map(\.path),
            ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d", "/tmp/e"]
        )
        XCTAssertEqual(
            snapshot.states[AppCommandID.showRepositoryOptions],
            AppCommandState(title: "Repository Options…", isEnabled: false)
        )
        XCTAssertEqual(
            snapshot.states[AppCommandID.openRepositoryOnGitHub],
            AppCommandState(title: "Open on GitHub", isEnabled: false)
        )
    }
}
