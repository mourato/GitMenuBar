@testable import GitMenuBar
import XCTest

@MainActor
final class GitManagerWorktreeCleanupUnitTests: XCTestCase {
    func testCherryPickedBranchIsTreatedAsMergedAndCanBeCleaned() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["checkout", "-b", "feature/cherry-picked"], in: repositoryURL)
        try "cherry-picked\n".write(
            to: repositoryURL.appendingPathComponent("cherry-picked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: cherry-picked"], in: repositoryURL)
        let featureCommit = try runGit(["rev-parse", "HEAD"], in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["checkout", "main"], in: repositoryURL)
        try runGit(["cherry-pick", featureCommit], in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let branch = try XCTUnwrap(snapshot.branches.first {
            !$0.reference.isRemote && $0.reference.name == "feature/cherry-picked"
        })
        XCTAssertEqual(branch.status, .mergedIntoDefault)

        let unit = try XCTUnwrap(snapshot.managementUnits.first {
            $0.branch.reference.name == "feature/cherry-picked"
        })
        let result = try await successfulCleanup(gitManager, units: [unit], snapshot: snapshot)

        XCTAssertEqual(result.items.map(\.status), [.succeeded], "\(result.items)")
        XCTAssertFalse(try runGit(["branch", "--format=%(refname:short)"], in: repositoryURL).contains("feature/cherry-picked"))
    }

    func testSafeCleanupSkipsBranchThatBecomesUnmerged() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["checkout", "-b", "feature/safe-race"], in: repositoryURL)
        try "safe race\n".write(
            to: repositoryURL.appendingPathComponent("safe-race.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: safe race"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
        try runGit(["merge", "--no-ff", "feature/safe-race", "-m", "merge safe race"], in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let unit = try XCTUnwrap(snapshot.cleanupUnits.first {
            $0.branch.reference.name == "feature/safe-race"
        })
        try runGit(["reset", "--hard", "HEAD~1"], in: repositoryURL)

        let result = await gitManager.performCleanupAsync(units: [unit], snapshot: snapshot)
        guard case let .success(batch) = result else {
            XCTFail("Expected cleanup batch success, got \(result)")
            return
        }

        XCTAssertEqual(
            batch.items.first?.status,
            .skipped(reason: "The branch is no longer merged into the default branch.")
        )
        XCTAssertTrue(
            try runGit(["show-ref", "--verify", "refs/heads/feature/safe-race"], in: repositoryURL)
                .contains("feature/safe-race")
        )
    }

    func testCleanupRejectsUnitFromAnotherRepository() async throws {
        let repositoryA = try createTemporaryGitRepository(testName: #function + "-a")
        let repositoryB = try createTemporaryGitRepository(testName: #function + "-b")
        try runGit(["branch", "feature/shared"], in: repositoryA)
        try runGit(["branch", "feature/shared"], in: repositoryB)

        let managerA = GitManager(repositoryPathOverride: repositoryA.path)
        let snapshotA = try await resolvedSnapshot(from: managerA)
        let managerB = GitManager(repositoryPathOverride: repositoryB.path)
        let snapshotB = try await resolvedSnapshot(from: managerB)
        let foreignUnit = try XCTUnwrap(snapshotB.managementUnits.first {
            $0.branch.reference.name == "feature/shared"
        })

        let result = await managerA.performCleanupAsync(units: [foreignUnit], snapshot: snapshotA)
        guard case let .success(batch) = result else {
            XCTFail("Expected cleanup batch success, got \(result)")
            return
        }

        XCTAssertEqual(
            batch.items.first?.status,
            .skipped(reason: "The cleanup unit belongs to another repository; it was skipped.")
        )
        XCTAssertTrue(
            try runGit(["show-ref", "--verify", "refs/heads/feature/shared"], in: repositoryA)
                .contains("feature/shared")
        )
    }

    func testUnmergedBranchCleanupUsesExplicitForceDeletePath() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["checkout", "-b", "feature/unmerged-cleanup"], in: repositoryURL)
        try "unmerged\n".write(
            to: repositoryURL.appendingPathComponent("unmerged-cleanup.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: unmerged cleanup"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let unit = try XCTUnwrap(snapshot.managementUnits.first {
            $0.branch.reference.name == "feature/unmerged-cleanup"
        })
        XCTAssertFalse(unit.branch.isMergedIntoDefault)

        let result = try await successfulCleanup(gitManager, units: [unit], snapshot: snapshot)

        XCTAssertEqual(result.items.map(\.status), [.succeeded], "\(result.items)")
        XCTAssertFalse(try runGit(["branch", "--format=%(refname:short)"], in: repositoryURL).contains("feature/unmerged-cleanup"))
    }

    func testUnmergedCleanPairedUnitRemovesWorktreeAndBranch() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["checkout", "-b", "feature/unmerged-pair"], in: repositoryURL)
        try "unmerged\n".write(
            to: repositoryURL.appendingPathComponent("unmerged-pair.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: unmerged pair"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
        let linkedURL = temporaryTestPath(testName: #function + "-worktree")
        try runGit(["worktree", "add", linkedURL.path, "feature/unmerged-pair"], in: repositoryURL)
        addTemporaryGitWorktreeCleanup(linkedURL, repositoryURL: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let unit = try XCTUnwrap(snapshot.managementUnits.first {
            $0.branch.reference.name == "feature/unmerged-pair"
        })
        XCTAssertEqual(unit.worktree?.status, .branchNotMerged)
        XCTAssertTrue(unit.isPaired)

        let result = try await successfulCleanup(gitManager, units: [unit], snapshot: snapshot)

        XCTAssertEqual(result.items.map(\.status), [.succeeded], "\(result.items)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkedURL.path))
        XCTAssertFalse(try runGit(["branch", "--format=%(refname:short)"], in: repositoryURL).contains("feature/unmerged-pair"))
    }

    func testWorktreeOnlyRemovalKeepsUnmergedBranch() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["checkout", "-b", "feature/keep-branch"], in: repositoryURL)
        try "keep branch\n".write(
            to: repositoryURL.appendingPathComponent("keep-branch.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repositoryURL)
        try runGit(["commit", "-m", "feat: keep branch"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
        let linkedURL = temporaryTestPath(testName: #function + "-worktree")
        try runGit(["worktree", "add", linkedURL.path, "feature/keep-branch"], in: repositoryURL)
        addTemporaryGitWorktreeCleanup(linkedURL, repositoryURL: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let pair = try XCTUnwrap(snapshot.managementUnits.first {
            $0.branch.reference.name == "feature/keep-branch"
        })
        let worktreeOnly = try XCTUnwrap(pair.removingWorktreeOnly())

        let result = try await successfulCleanup(gitManager, units: [worktreeOnly], snapshot: snapshot)

        XCTAssertEqual(result.items.map(\.status), [.succeeded], "\(result.items)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkedURL.path))
        XCTAssertTrue(try runGit(["show-ref", "--verify", "refs/heads/feature/keep-branch"], in: repositoryURL).contains("feature/keep-branch"))
    }

    func testDetachedCleanWorktreeCanBeRemoved() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        let linkedURL = temporaryTestPath(testName: #function + "-worktree")
        try runGit(["worktree", "add", "--detach", linkedURL.path, "main"], in: repositoryURL)
        addTemporaryGitWorktreeCleanup(linkedURL, repositoryURL: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let unit = try XCTUnwrap(snapshot.managementUnits.first {
            guard let path = $0.worktree?.worktree.path else { return false }
            return GitRepositoryContext.normalizedPath(path) == GitRepositoryContext.normalizedPath(linkedURL.path)
        })
        XCTAssertEqual(unit.worktree?.status, .detached)
        XCTAssertTrue(unit.isWorktreeOnlyAction)

        let result = try await successfulCleanup(gitManager, units: [unit], snapshot: snapshot)

        XCTAssertEqual(result.items.map(\.status), [.succeeded], "\(result.items)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkedURL.path))
    }

    func testBranchOnlyActionDoesNotDeleteBranchCheckedOutInWorktree() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/branch-only"], in: repositoryURL)
        let linkedURL = temporaryTestPath(testName: #function + "-worktree")
        try runGit(["worktree", "add", linkedURL.path, "feature/branch-only"], in: repositoryURL)
        addTemporaryGitWorktreeCleanup(linkedURL, repositoryURL: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let pair = try XCTUnwrap(snapshot.managementUnits.first {
            $0.branch.reference.name == "feature/branch-only"
        })
        let branchOnly = pair.deletingBranchOnly()

        let result = try await successfulCleanup(gitManager, units: [branchOnly], snapshot: snapshot)

        XCTAssertEqual(result.items.first?.status, .skipped(reason: "The branch is checked out in a worktree."))
        XCTAssertTrue(try runGit(["show-ref", "--verify", "refs/heads/feature/branch-only"], in: repositoryURL).contains("feature/branch-only"))
    }

    func testExplicitUpstreamCleanupDeletesOnlySelectedRemoteBranch() async throws {
        let repositoryURL = try createTemporaryGitRepository(testName: #function)
        let remoteURL = temporaryTestPath(testName: #function + "-remote")
        try runGit(["clone", "--bare", repositoryURL.path, remoteURL.path], in: repositoryURL.deletingLastPathComponent())
        try runGit(["remote", "add", "upstream", remoteURL.path], in: repositoryURL)
        try runGit(["push", "upstream", "main"], in: repositoryURL)
        try runGit(["branch", "feature/upstream"], in: repositoryURL)
        try runGit(["push", "upstream", "feature/upstream"], in: repositoryURL)
        try runGit(["fetch", "upstream"], in: repositoryURL)

        let gitManager = GitManager(repositoryPathOverride: repositoryURL.path)
        let snapshot = try await resolvedSnapshot(from: gitManager)
        let remoteBranch = try XCTUnwrap(snapshot.branches.first {
            $0.reference.isRemote
                && $0.reference.remoteName == "upstream"
                && $0.reference.name == "feature/upstream"
        })
        XCTAssertEqual(remoteBranch.status, .mergedIntoDefault)

        let result = try await successfulCleanup(
            gitManager,
            targets: [.remoteBranch(remoteBranch)],
            snapshot: snapshot
        )

        XCTAssertEqual(result.items.first?.status, .succeeded)
        try runGit(["fetch", "--prune", "upstream"], in: repositoryURL)
        let refs = try runGit(["for-each-ref", "--format=%(refname:short)", "refs/remotes/upstream"], in: repositoryURL)
        XCTAssertFalse(refs.contains("upstream/feature/upstream"))
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
