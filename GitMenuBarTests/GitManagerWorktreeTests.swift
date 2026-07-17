@testable import GitMenuBar
import XCTest

final class GitManagerWorktreeTests: XCTestCase {
    func testResolveWorktreeSnapshotFindsMergedAndUnmergedBranches() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["checkout", "-b", "feature/merged"], in: repositoryURL)
        try "merged\n".write(
            to: repositoryURL.appendingPathComponent("merged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: merged"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
        try runGit(["merge", "--no-ff", "feature/merged", "-m", "merge feature"], in: repositoryURL)
        try runGit(["checkout", "-b", "feature/unmerged"], in: repositoryURL)
        try "unmerged\n".write(
            to: repositoryURL.appendingPathComponent("unmerged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: unmerged"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let result = await gitManager.resolveWorktreeSnapshotAsync()

        guard case let .success(snapshot) = result else {
            XCTFail("Expected snapshot success, got \(result)")
            return
        }
        XCTAssertEqual(snapshot.defaultBranchName, "main")
        XCTAssertEqual(
            snapshot.branches.first { $0.reference.name == "feature/merged" }?.status,
            .mergedIntoDefault
        )
        XCTAssertEqual(
            snapshot.branches.first { $0.reference.name == "feature/unmerged" }?.status,
            .notMerged
        )
    }

    func testResolveWorktreeSnapshotFindsLinkedWorktreeAndDirtyState() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/linked"], in: repositoryURL)
        let linkedURL = repositoryURL.deletingLastPathComponent()
            .appendingPathComponent("\(repositoryURL.lastPathComponent)-linked")
        try runGit(["worktree", "add", linkedURL.path, "feature/linked"], in: repositoryURL)
        try "changed\n".write(
            to: linkedURL.appendingPathComponent("dirty.txt"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: linkedURL) }

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let result = await gitManager.resolveWorktreeSnapshotAsync()

        guard case let .success(snapshot) = result else {
            XCTFail("Expected snapshot success, got \(result)")
            return
        }
        let linked = snapshot.worktrees.first {
            URL(fileURLWithPath: $0.worktree.path).standardizedFileURL
                == linkedURL.standardizedFileURL
        }
        XCTAssertEqual(linked?.worktree.branchName, "feature/linked")
        XCTAssertEqual(linked?.worktree.workingTreeState, .dirty)
        XCTAssertEqual(linked?.status, .dirty)
    }
}
