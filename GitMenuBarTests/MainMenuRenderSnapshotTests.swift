@testable import GitMenuBar
import XCTest

final class MainMenuRenderSnapshotTests: XCTestCase {
    func testBuildUsesCustomProjectNameForCurrentRepository() {
        let snapshot = MainMenuRenderSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitHistory: [],
            currentHash: "",
            remoteUrl: "",
            availableBranches: [],
            currentBranch: "",
            isStagedSectionCollapsed: false,
            isUnstagedSectionCollapsed: false,
            isHistorySectionCollapsed: false,
            recentProjects: [
                ProjectReference(path: "/tmp/worktrees/client-a", name: "Client A")
            ],
            currentRepoPath: "/tmp/worktrees/../worktrees/client-a",
            isCommitInFuture: { _ in false }
        )

        XCTAssertEqual(snapshot.currentProjectName, "Client A")
    }

    func testBuildFallsBackToFolderNameWhenCurrentProjectIsMissing() {
        let snapshot = MainMenuRenderSnapshot.build(
            stagedFiles: [],
            changedFiles: [],
            commitHistory: [],
            currentHash: "",
            remoteUrl: "",
            availableBranches: [],
            currentBranch: "",
            isStagedSectionCollapsed: false,
            isUnstagedSectionCollapsed: false,
            isHistorySectionCollapsed: false,
            recentProjects: [],
            currentRepoPath: "/tmp/worktrees/client-a",
            isCommitInFuture: { _ in false }
        )

        XCTAssertEqual(snapshot.currentProjectName, "client-a")
    }
}
