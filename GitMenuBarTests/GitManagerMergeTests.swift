@testable import GitMenuBar
import XCTest

final class GitManagerMergeTests: XCTestCase {
    private func makeFeatureBranch(named name: String, in repoURL: URL) throws {
        try runGit(["checkout", "-b", name], in: repoURL)
        try "feature change\n".write(
            to: repoURL.appendingPathComponent("feature.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "feat: \(name)"], in: repoURL)
        try runGit(["checkout", "main"], in: repoURL)
    }

    func testMergeToDefaultBranchKeepMergesSuccessfully() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try makeFeatureBranch(named: "feature/keep", in: repoURL)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        let result = await gitManager.mergeToDefaultBranchAsync(
            featureBranch: "feature/keep",
            cleanupOption: .keep
        )

        switch result {
        case let .success(mergeResult):
            XCTAssertTrue(mergeResult.didMerge)
            XCTAssertFalse(mergeResult.didDeleteLocal)
            XCTAssertFalse(mergeResult.didDeleteRemote)
            XCTAssertEqual(mergeResult.defaultBranchName, "main")
        case let .failure(error):
            XCTFail("Merge should succeed: \(error.localizedDescription)")
        }

        // The feature branch should still exist on the local repo.
        let remaining = try runGit(["branch", "--format=%(refname:short)"], in: repoURL)
        XCTAssertTrue(remaining.contains("feature/keep"))
    }

    func testMergeToDefaultBranchDeleteLocalRemovesBranch() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try makeFeatureBranch(named: "feature/delete-local", in: repoURL)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        let result = await gitManager.mergeToDefaultBranchAsync(
            featureBranch: "feature/delete-local",
            cleanupOption: .deleteLocal
        )

        switch result {
        case let .success(mergeResult):
            XCTAssertTrue(mergeResult.didMerge)
            XCTAssertTrue(mergeResult.didDeleteLocal)
        case let .failure(error):
            XCTFail("Merge + local delete should succeed: \(error.localizedDescription)")
        }

        let remaining = try runGit(["branch", "--format=%(refname:short)"], in: repoURL)
        XCTAssertFalse(remaining.contains("feature/delete-local"))
    }

    func testMergeToDefaultBranchConflictReturnsFailure() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)

        // Create a feature branch that edits the same file as main, causing a conflict.
        try "main content\n".write(
            to: repoURL.appendingPathComponent("shared.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "chore: base"], in: repoURL)

        try runGit(["checkout", "-b", "feature/conflict"], in: repoURL)
        try "feature content\n".write(
            to: repoURL.appendingPathComponent("shared.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "feat: feature edit"], in: repoURL)
        try runGit(["checkout", "main"], in: repoURL)

        try "main conflicting content\n".write(
            to: repoURL.appendingPathComponent("shared.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "feat: main edit"], in: repoURL)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        let result = await gitManager.mergeToDefaultBranchAsync(
            featureBranch: "feature/conflict",
            cleanupOption: .keep
        )

        switch result {
        case .success:
            XCTFail("Merging conflicting branches should fail")
        case let .failure(error):
            XCTAssertTrue(
                error.localizedDescription.contains("conflict")
                    || error.localizedDescription.contains("Merge failed"),
                "Expected a conflict error, got: \(error.localizedDescription)"
            )
        }
    }

    /// Uses a bare clone as a local remote so the push/delete of the remote
    /// branch is reliable under concurrent test execution (no object transfer).
    func testMergeToDefaultBranchDeleteLocalAndRemote() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try "base\n".write(
            to: repoURL.appendingPathComponent("base.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "chore: base"], in: repoURL)
        try runGit(["branch", "feature/remote"], in: repoURL)

        let remote = repoURL.deletingLastPathComponent()
            .appendingPathComponent(#function + "-remote-" + UUID().uuidString + ".git")
        try runGit(["clone", "--bare", repoURL.path, remote.path], in: repoURL.deletingLastPathComponent())
        try runGit(["remote", "add", "origin", remote.path], in: repoURL)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        var succeeded = false
        var lastError: String?
        for _ in 0 ..< 5 {
            let result = await gitManager.mergeToDefaultBranchAsync(
                featureBranch: "feature/remote",
                cleanupOption: .deleteLocalAndRemote
            )
            if case let .success(mergeResult) = result {
                succeeded = true
                XCTAssertTrue(mergeResult.didDeleteLocal)
                XCTAssertTrue(mergeResult.didDeleteRemote)
                break
            } else if case let .failure(error) = result {
                lastError = error.localizedDescription
                usleep(50000)
            }
        }
        XCTAssertTrue(succeeded, "Merge + remote delete should succeed (last error: \(lastError ?? "none"))")

        try runGit(["fetch", "--prune", "origin"], in: repoURL)
        let remoteBranches = await gitManager.fetchRemoteBranchesAsync()
        XCTAssertFalse(
            remoteBranches.contains("feature/remote"),
            "Remote branch should be gone after delete, got: \(remoteBranches)"
        )
    }
}
