@testable import GitMenuBar
import XCTest

final class GitWorktreeIntegrationTests: XCTestCase {
    func testSnapshotRepresentsMergedUnmergedAndWorktreeStates() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        let paths = try makeIntegrationFixture(in: repositoryURL)
        defer { removeFixture(paths, repositoryURL: repositoryURL) }

        let manager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: manager)

        XCTAssertEqual(snapshot.defaultBranchName, "main")
        XCTAssertEqual(localStatus("feature/merged", in: snapshot), .mergedIntoDefault)
        XCTAssertEqual(localStatus("feature/unmerged", in: snapshot), .notMerged)
        XCTAssertEqual(worktreeStatus(paths.clean.path, in: snapshot), .eligible)
        XCTAssertEqual(worktreeStatus(paths.dirty.path, in: snapshot), .dirty)
        XCTAssertEqual(worktreeStatus(paths.detached.path, in: snapshot), .detached)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.clean.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.dirty.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.detached.path))
    }

    func testCleanupUpdatesRefsAndDirectoriesWhileContinuingAfterSkippedItem() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try makeMergedBranch(named: "feature/merged", in: repositoryURL)
        try runGit(["branch", "feature/clean"], in: repositoryURL)
        try runGit(["branch", "feature/dirty"], in: repositoryURL)

        let root = repositoryURL.deletingLastPathComponent()
        let cleanURL = root.appendingPathComponent("\(repositoryURL.lastPathComponent)-clean")
        let dirtyURL = root.appendingPathComponent("\(repositoryURL.lastPathComponent)-dirty")
        try runGit(["worktree", "add", cleanURL.path, "feature/clean"], in: repositoryURL)
        try runGit(["worktree", "add", dirtyURL.path, "feature/dirty"], in: repositoryURL)
        try "local change\n".write(
            to: dirtyURL.appendingPathComponent("dirty.txt"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            removeWorktrees([cleanURL, dirtyURL], repositoryURL: repositoryURL)
            try? FileManager.default.removeItem(at: repositoryURL)
        }

        let manager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: manager)
        let merged = try XCTUnwrap(localBranch("feature/merged", in: snapshot))
        let clean = try XCTUnwrap(worktree(cleanURL.path, in: snapshot))
        let dirty = try XCTUnwrap(worktree(dirtyURL.path, in: snapshot))

        let result = try await successfulCleanup(
            manager,
            targets: [.localBranch(merged), .worktree(dirty), .worktree(clean)],
            snapshot: snapshot
        )

        XCTAssertEqual(result.succeededCount, 2)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.items[1].status, .skipped(reason: "The worktree is no longer eligible for cleanup."))
        XCTAssertFalse(hasLocalBranch("feature/merged", in: repositoryURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        XCTAssertTrue(hasLocalBranch("feature/dirty", in: repositoryURL))
    }

    private struct FixturePaths {
        let clean: URL
        let dirty: URL
        let detached: URL
    }

    private func makeIntegrationFixture(in repositoryURL: URL) throws -> FixturePaths {
        try makeMergedBranch(named: "feature/merged", in: repositoryURL)
        try makeUnmergedBranch(named: "feature/unmerged", in: repositoryURL)
        try runGit(["branch", "feature/clean"], in: repositoryURL)
        try runGit(["branch", "feature/dirty"], in: repositoryURL)

        let root = repositoryURL.deletingLastPathComponent()
        let cleanURL = root.appendingPathComponent("\(repositoryURL.lastPathComponent)-clean")
        let dirtyURL = root.appendingPathComponent("\(repositoryURL.lastPathComponent)-dirty")
        let detachedURL = root.appendingPathComponent("\(repositoryURL.lastPathComponent)-detached")
        try runGit(["worktree", "add", cleanURL.path, "feature/clean"], in: repositoryURL)
        try runGit(["worktree", "add", dirtyURL.path, "feature/dirty"], in: repositoryURL)
        try runGit(["worktree", "add", "--detach", detachedURL.path, "HEAD"], in: repositoryURL)
        try "local change\n".write(
            to: dirtyURL.appendingPathComponent("dirty.txt"),
            atomically: true,
            encoding: .utf8
        )
        return FixturePaths(clean: cleanURL, dirty: dirtyURL, detached: detachedURL)
    }

    private func makeMergedBranch(named name: String, in repositoryURL: URL) throws {
        try runGit(["checkout", "-b", name], in: repositoryURL)
        try "\(name)\n".write(
            to: repositoryURL.appendingPathComponent("\(name.replacingOccurrences(of: "/", with: "-")).txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: \(name)"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
        try runGit(["merge", "--no-ff", name, "-m", "merge \(name)"], in: repositoryURL)
    }

    private func makeUnmergedBranch(named name: String, in repositoryURL: URL) throws {
        try runGit(["checkout", "-b", name], in: repositoryURL)
        try "unmerged\n".write(
            to: repositoryURL.appendingPathComponent("unmerged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: \(name)"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
    }

    private func resolvedSnapshot(from manager: GitManager) async throws -> GitWorktreeSnapshot {
        let result = await manager.resolveWorktreeSnapshotAsync()
        guard case let .success(snapshot) = result else {
            XCTFail("Expected snapshot success, got \(result)")
            throw NSError(domain: "GitTest", code: 1)
        }
        return snapshot
    }

    private func successfulCleanup(
        _ manager: GitManager,
        targets: [GitCleanupTarget],
        snapshot: GitWorktreeSnapshot
    ) async throws -> GitCleanupBatchResult {
        let result = await manager.performCleanupAsync(targets: targets, snapshot: snapshot)
        guard case let .success(batch) = result else {
            XCTFail("Expected cleanup batch success, got \(result)")
            throw NSError(domain: "GitTest", code: 2)
        }
        return batch
    }

    private func localBranch(_ name: String, in snapshot: GitWorktreeSnapshot) -> GitBranchCleanupInfo? {
        snapshot.branches.first { !$0.reference.isRemote && $0.reference.name == name }
    }

    private func localStatus(_ name: String, in snapshot: GitWorktreeSnapshot) -> GitBranchCleanupStatus? {
        localBranch(name, in: snapshot)?.status
    }

    private func worktree(_ path: String, in snapshot: GitWorktreeSnapshot) -> GitWorktreeCleanupInfo? {
        snapshot.worktrees.first {
            URL(fileURLWithPath: $0.worktree.path).standardizedFileURL.path
                == URL(fileURLWithPath: path).standardizedFileURL.path
        }
    }

    private func worktreeStatus(_ path: String, in snapshot: GitWorktreeSnapshot) -> GitWorktreeCleanupStatus? {
        worktree(path, in: snapshot)?.status
    }

    private func hasLocalBranch(_ name: String, in repositoryURL: URL) -> Bool {
        (try? runGit(["show-ref", "--verify", "--quiet", "refs/heads/\(name)"], in: repositoryURL)) != nil
    }

    private func removeFixture(_ paths: FixturePaths, repositoryURL: URL) {
        removeWorktrees([paths.clean, paths.dirty, paths.detached], repositoryURL: repositoryURL)
        try? FileManager.default.removeItem(at: paths.clean)
        try? FileManager.default.removeItem(at: paths.dirty)
        try? FileManager.default.removeItem(at: paths.detached)
        try? FileManager.default.removeItem(at: repositoryURL)
    }

    private func removeWorktrees(_ paths: [URL], repositoryURL: URL) {
        for path in paths {
            try? runGit(["worktree", "remove", "--force", path.path], in: repositoryURL)
            try? FileManager.default.removeItem(at: path)
        }
    }
}
