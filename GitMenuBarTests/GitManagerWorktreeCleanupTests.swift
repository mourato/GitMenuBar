@testable import GitMenuBar
import XCTest

@MainActor
final class GitManagerWorktreeCleanupTests: XCTestCase {
    func testBatchCleanupRemovesMergedBranchAndCleanWorktree() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/worktree"], in: repositoryURL)
        let linkedURL = repositoryURL.deletingLastPathComponent()
            .appendingPathComponent("\(repositoryURL.lastPathComponent)-linked")
        try runGit(["worktree", "add", linkedURL.path, "feature/worktree"], in: repositoryURL)
        addTemporaryGitWorktreeCleanup(linkedURL, repositoryURL: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let unit = try XCTUnwrap(snapshot.cleanupUnits.first {
            $0.branch.reference.name == "feature/worktree"
        })

        let result = try await successfulCleanup(
            gitManager,
            units: [unit],
            snapshot: snapshot
        )

        XCTAssertEqual(result.items.map(\.status), [.succeeded])
        XCTAssertFalse(try runGit(["branch", "--format=%(refname:short)"], in: repositoryURL).contains("feature/worktree"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkedURL.path))
    }

    func testBatchCleanupSkipsStaleBranchAndContinues() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try makeMergedBranch(named: "feature/stale", in: repositoryURL)
        try makeMergedBranch(named: "feature/kept", in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let stale = try XCTUnwrap(snapshot.branches.first {
            !$0.reference.isRemote && $0.reference.name == "feature/stale"
        })
        let kept = try XCTUnwrap(snapshot.branches.first {
            !$0.reference.isRemote && $0.reference.name == "feature/kept"
        })

        try runGit(["checkout", "feature/stale"], in: repositoryURL)
        try "changed after analysis\n".write(
            to: repositoryURL.appendingPathComponent("stale.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: stale update"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)

        let result = try await successfulCleanup(
            gitManager,
            targets: [.localBranch(stale), .localBranch(kept)],
            snapshot: snapshot
        )

        XCTAssertEqual(result.items[0].status, .skipped(reason: "The branch changed since analysis; it was skipped."))
        XCTAssertEqual(result.items[1].status, .succeeded)
        XCTAssertTrue(try runGit(["show-ref", "--verify", "refs/heads/feature/stale"], in: repositoryURL).contains("feature/stale"))
        XCTAssertFalse(try runGit(["branch", "--format=%(refname:short)"], in: repositoryURL).contains("feature/kept"))
    }

    func testBatchCleanupDoesNotRemoveDirtyWorktree() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/dirty"], in: repositoryURL)
        let linkedURL = repositoryURL.deletingLastPathComponent()
            .appendingPathComponent("\(repositoryURL.lastPathComponent)-dirty")
        try runGit(["worktree", "add", linkedURL.path, "feature/dirty"], in: repositoryURL)
        addTemporaryGitWorktreeCleanup(linkedURL, repositoryURL: repositoryURL)
        try "uncommitted\n".write(
            to: linkedURL.appendingPathComponent("dirty.txt"),
            atomically: true,
            encoding: .utf8
        )

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let worktree = try XCTUnwrap(snapshot.worktrees.first {
            $0.worktree.branchName == "feature/dirty"
        })

        let result = try await successfulCleanup(
            gitManager,
            targets: [.worktree(worktree)],
            snapshot: snapshot
        )

        XCTAssertEqual(result.items.first?.status, .skipped(reason: "The worktree is no longer eligible for cleanup."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkedURL.path))
    }

    func testBatchCleanupSkipsWorktreeWhenItsBranchChangedWithSameHead() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/worktree"], in: repositoryURL)
        try runGit(["branch", "feature/other"], in: repositoryURL)
        let linkedURL = repositoryURL.deletingLastPathComponent()
            .appendingPathComponent("\(repositoryURL.lastPathComponent)-same-head")
        try runGit(["worktree", "add", linkedURL.path, "feature/worktree"], in: repositoryURL)
        addTemporaryGitWorktreeCleanup(linkedURL, repositoryURL: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let unit = try XCTUnwrap(snapshot.cleanupUnits.first { $0.branch.reference.name == "feature/worktree" })

        try runGit(["checkout", "feature/other"], in: linkedURL)
        let result = try await successfulCleanup(gitManager, units: [unit], snapshot: snapshot)

        XCTAssertEqual(result.items.first?.status, .skipped(reason: "The worktree changed or is no longer eligible for cleanup."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkedURL.path))
        XCTAssertTrue(try runGit(["show-ref", "--verify", "refs/heads/feature/worktree"], in: repositoryURL).contains("feature/worktree"))
    }

    func testBatchCleanupDoesNotRemoveMainWorktree() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let main = try XCTUnwrap(snapshot.worktrees.first { $0.worktree.isMainWorktree })
        let unsafeMain = GitWorktreeCleanupInfo(worktree: main.worktree, status: .eligible)

        let result = try await successfulCleanup(gitManager, targets: [.worktree(unsafeMain)], snapshot: snapshot)

        XCTAssertEqual(result.items.first?.status, .skipped(reason: "The current worktree cannot be removed."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryURL.path))
    }

    func testBatchCleanupSkipsAllTargetsWhenRepositoryIdentityChanges() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try makeMergedBranch(named: "feature/identity", in: repositoryURL)
        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let branch = try XCTUnwrap(snapshot.branches.first { $0.reference.name == "feature/identity" && !$0.reference.isRemote })
        let changedSnapshot = GitWorktreeSnapshot(
            repositoryPath: snapshot.repositoryPath,
            defaultBranchName: snapshot.defaultBranchName,
            defaultBranchRef: snapshot.defaultBranchRef,
            analysisDescription: snapshot.analysisDescription,
            worktrees: snapshot.worktrees,
            branches: snapshot.branches,
            repositoryIdentity: "/different-shared-repository",
            protectedWorktreePaths: snapshot.protectedWorktreePaths,
            cleanupUnits: snapshot.cleanupUnits
        )

        let result = try await successfulCleanup(gitManager, targets: [.localBranch(branch)], snapshot: changedSnapshot)

        XCTAssertEqual(result.items.first?.status, .skipped(reason: "The shared repository identity changed; cleanup was skipped."))
        XCTAssertTrue(try runGit(["show-ref", "--verify", "refs/heads/feature/identity"], in: repositoryURL).contains("feature/identity"))
    }

    func testBatchCleanupSkipsCurrentAndProtectedBranches() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/current"], in: repositoryURL)
        try runGit(["checkout", "feature/current"], in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let current = try XCTUnwrap(snapshot.branches.first {
            !$0.reference.isRemote && $0.reference.name == "feature/current"
        })
        let main = try XCTUnwrap(snapshot.branches.first {
            !$0.reference.isRemote && $0.reference.name == "main"
        })

        let result = try await successfulCleanup(
            gitManager,
            targets: [.localBranch(current), .localBranch(main)],
            snapshot: snapshot
        )

        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy {
            if case .skipped = $0.status {
                return true
            }
            return false
        })
        XCTAssertTrue(try runGit(["show-ref", "--verify", "refs/heads/main"], in: repositoryURL).contains("main"))
    }

    func testBatchCleanupSkipsLockedWorktree() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/locked"], in: repositoryURL)
        let linkedURL = repositoryURL.deletingLastPathComponent()
            .appendingPathComponent("\(repositoryURL.lastPathComponent)-locked")
        try runGit(["worktree", "add", linkedURL.path, "feature/locked"], in: repositoryURL)
        addTemporaryGitWorktreeCleanup(linkedURL, repositoryURL: repositoryURL)
        try runGit(["worktree", "lock", "--reason", "build", linkedURL.path], in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let worktree = try XCTUnwrap(snapshot.worktrees.first {
            $0.worktree.branchName == "feature/locked"
        })

        let result = try await successfulCleanup(
            gitManager,
            targets: [.worktree(worktree)],
            snapshot: snapshot
        )

        XCTAssertEqual(result.items.first?.status, .skipped(reason: "The worktree is no longer eligible for cleanup."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkedURL.path))
    }

    func testExplicitRemoteCleanupDeletesOnlySelectedRemoteBranch() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        let remoteURL = temporaryTestPath(testName: #function + "-remote")
        try runGit(["clone", "--bare", repositoryURL.path, remoteURL.path], in: repositoryURL.deletingLastPathComponent())
        try runGit(["remote", "add", "origin", remoteURL.path], in: repositoryURL)
        try runGit(["push", "-u", "origin", "main"], in: repositoryURL)
        try runGit(["branch", "feature/remote"], in: repositoryURL)
        try runGit(["push", "origin", "feature/remote"], in: repositoryURL)
        try runGit(["fetch", "origin"], in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let remoteBranch = try XCTUnwrap(snapshot.branches.first {
            $0.reference.isRemote && $0.reference.name == "feature/remote"
        })

        let result = try await successfulCleanup(
            gitManager,
            targets: [.remoteBranch(remoteBranch)],
            snapshot: snapshot
        )

        XCTAssertEqual(result.items.first?.status, .succeeded)
        try runGit(["fetch", "--prune", "origin"], in: repositoryURL)
        let remoteBranches = await gitManager.fetchRemoteBranchesAsync()
        XCTAssertFalse(remoteBranches.contains("feature/remote"))
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

    private func resolvedSnapshot(from manager: GitManager) async throws -> GitWorktreeSnapshot {
        let result = await manager.resolveWorktreeSnapshotAsync()
        guard case let .success(snapshot) = result else {
            XCTFail("Expected worktree snapshot, got \(result)")
            throw NSError(domain: "GitTest", code: 1)
        }
        return snapshot
    }

    private func successfulCleanup(
        _ manager: GitManager,
        units: [GitCleanupUnit],
        snapshot: GitWorktreeSnapshot
    ) async throws -> GitCleanupBatchResult {
        let result = await manager.performCleanupAsync(units: units, snapshot: snapshot)
        guard case let .success(batch) = result else {
            XCTFail("Expected cleanup batch success, got \(result)")
            throw NSError(domain: "GitTest", code: 2)
        }
        return batch
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
}
