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
                isGitHubAuthenticated: true
            )
        )

        XCTAssertEqual(snapshot.states[.commit], AppCommandState(title: "Commit", isEnabled: false))
        XCTAssertEqual(snapshot.states[.sync], AppCommandState(title: "Sync Changes", isEnabled: true))
        XCTAssertEqual(
            snapshot.states[.showRepositoryOptions],
            AppCommandState(title: "Repository Options…", isEnabled: true)
        )
        XCTAssertEqual(
            snapshot.states[.revealRepositoryInFinder],
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
                isGitHubAuthenticated: false
            )
        )

        XCTAssertEqual(snapshot.recentProjects.count, 5)
        XCTAssertEqual(
            snapshot.recentProjects.map(\.path),
            ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d", "/tmp/e"]
        )
        XCTAssertEqual(
            snapshot.states[.showRepositoryOptions],
            AppCommandState(title: "Repository Options…", isEnabled: false)
        )
        XCTAssertEqual(
            snapshot.states[.openRepositoryOnGitHub],
            AppCommandState(title: "Open on GitHub", isEnabled: false)
        )
    }
}
