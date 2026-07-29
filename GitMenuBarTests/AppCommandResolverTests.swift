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
                currentRepoPath: "/tmp/current/../current",
                remoteUrl: "git@github.com:saihgupr/GitMenuBar.git",
                recentProjects: [],
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
            AppCommandState(title: "Repository Options", isEnabled: true)
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
                recentProjects: [
                    ProjectReference(path: "/tmp/current", name: "Current Project"),
                    ProjectReference(path: "/tmp/a", name: "Client A"),
                    ProjectReference(path: "/tmp/b", name: "Client B"),
                    ProjectReference(path: "/tmp/c", name: "Client C"),
                    ProjectReference(path: "/tmp/d", name: "Client D"),
                    ProjectReference(path: "/tmp/e", name: "Client E"),
                    ProjectReference(path: "/tmp/f", name: "Client F")
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
            snapshot.recentProjects.map(\.title),
            ["Client A", "Client B", "Client C", "Client D", "Client E"]
        )
        XCTAssertEqual(
            snapshot.states[AppCommandID.showRepositoryOptions],
            AppCommandState(title: "Repository Options", isEnabled: false)
        )
        XCTAssertEqual(
            snapshot.states[AppCommandID.openRepositoryOnGitHub],
            AppCommandState(title: "Open on GitHub", isEnabled: false)
        )
    }
}
