@testable import GitMenuBar
import XCTest

final class ProjectCleanupStoreTests: XCTestCase {
    func testRowsKeepEveryProjectAndAssignSharedIdentityToOneRow() {
        let first = ProjectReference(path: "/tmp/project-a", name: "A")
        let second = ProjectReference(path: "/tmp/project-b", name: "B")
        let snapshot = GitWorktreeSnapshot(
            repositoryPath: first.path,
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "local",
            worktrees: [],
            branches: [],
            repositoryIdentity: "/shared"
        )
        let analysis = GitCleanupAnalysis(
            repositoryPath: first.path,
            repositoryIdentity: "/shared",
            defaultBranchRef: "refs/heads/main",
            snapshot: snapshot
        )

        let rows = ProjectCleanupRow.projectRows(
            projects: [first, second],
            analyses: [
                first.path: .success(analysis),
                second.path: .success(analysis)
            ]
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.filter(\.isCanonical).count, 1)
        XCTAssertEqual(rows.filter(\.isShared).count, 1)
    }

    func testRowsKeepUnavailableProjectsVisible() {
        let project = ProjectReference(path: "/tmp/unavailable")

        let rows = ProjectCleanupRow.projectRows(
            projects: [project],
            analyses: [project.path: .failure("Repository is unavailable.")]
        )

        XCTAssertEqual(rows.first?.unavailableReason, "Repository is unavailable.")
        XCTAssertFalse(rows.first?.isCanonical == true)
    }
}
