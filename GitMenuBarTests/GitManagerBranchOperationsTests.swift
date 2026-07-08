@testable import GitMenuBar
import XCTest

final class GitManagerBranchOperationsTests: XCTestCase {
    /// Sets up a local repo that already has a remote-tracking ref for
    /// `origin/feature/pushed` and configures the local `feature/pushed` branch to
    /// track it. This is deterministic and avoids flaky real network pushes.
    private func prepareRepoWithRemoteTracking(testName: String) throws -> URL {
        let repoURL = try createTemporaryGitRepository(testName: testName + "-base")
        try runGit(["branch", "feature/pushed"], in: repoURL)
        // A configured origin is required for `branch @{u}` / set-upstream-to to
        // resolve the remote-tracking ref. The URL is irrelevant (no real fetch).
        try runGit(["remote", "add", "origin", repoURL.path], in: repoURL)
        let headSHA = try runGit(["rev-parse", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["update-ref", "refs/remotes/origin/feature/pushed", headSHA], in: repoURL)
        try runGit(["branch", "--set-upstream-to", "origin/feature/pushed", "feature/pushed"], in: repoURL)
        return repoURL
    }

    /// Prepares a repo with a committed branch, then clones it into a bare
    /// remote. Because the remote already contains the branch's commit, the
    /// subsequent `git push` only creates a ref (no object transfer), which is
    /// reliable under concurrent test execution.
    private func prepareRepoWithClonedRemote(testName: String) throws -> URL {
        let repoURL = try createTemporaryGitRepository(testName: testName + "-base")
        try "change\n".write(
            to: repoURL.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "feat: change"], in: repoURL)
        try runGit(["branch", "feature/to-push"], in: repoURL)

        let remote = repoURL.deletingLastPathComponent()
            .appendingPathComponent(testName + "-remote-" + UUID().uuidString + ".git")
        try runGit(["clone", "--bare", repoURL.path, remote.path], in: repoURL.deletingLastPathComponent())
        try runGit(["remote", "add", "origin", remote.path], in: repoURL)
        return repoURL
    }

    func testGetDefaultBranchNameAsyncReturnsNonEmpty() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        let defaultBranch = await gitManager.getDefaultBranchNameAsync()

        XCTAssertFalse(defaultBranch.isEmpty)
        XCTAssertTrue(["main", "master"].contains(defaultBranch))
    }

    func testFetchLocalBranchesAsyncIncludesCreatedBranch() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        try runGit(["branch", "feature/test"], in: repoURL)
        try runGit(["branch", "bugfix/other"], in: repoURL)

        let localBranches = await gitManager.fetchLocalBranchesAsync()

        XCTAssertTrue(localBranches.contains("main"))
        XCTAssertTrue(localBranches.contains("feature/test"))
        XCTAssertTrue(localBranches.contains("bugfix/other"))
    }

    func testFetchLocalBranchesAsyncExcludesRemotePrefixes() async throws {
        let repoURL = try prepareRepoWithRemoteTracking(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        let localBranches = await gitManager.fetchLocalBranchesAsync()

        XCTAssertFalse(localBranches.contains(where: { $0.contains("origin/") }))
        XCTAssertTrue(localBranches.contains("feature/pushed"))
    }

    func testFetchRemoteBranchesAsyncStripsOriginPrefix() async throws {
        let repoURL = try prepareRepoWithRemoteTracking(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        let remoteBranches = await gitManager.fetchRemoteBranchesAsync()

        XCTAssertTrue(remoteBranches.contains("feature/pushed"))
        XCTAssertFalse(remoteBranches.contains(where: { $0.contains("origin/") }))
    }

    func testResolveBranchInfoAsyncMarksCurrentBranch() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        try runGit(["branch", "feature/test"], in: repoURL)

        let infos = await gitManager.resolveBranchInfoAsync()

        let current = infos.first { $0.isCurrent }
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.name, "main")
        XCTAssertTrue(current?.isLocal ?? false)
    }

    func testResolveBranchInfoAsyncSeparatesLocalAndRemote() async throws {
        let repoURL = try prepareRepoWithRemoteTracking(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        let infos = await gitManager.resolveBranchInfoAsync()

        let localPushed = infos.first { $0.isLocal && $0.name == "feature/pushed" }
        XCTAssertNotNil(localPushed, "Local branch 'feature/pushed' should be present")
        XCTAssertNotEqual(localPushed?.trackingStatus, .noRemote, "Pushed branch should report an upstream status")

        // The remote-only branch list should not duplicate branches that also exist locally.
        let remoteInfos = infos.filter(\.isRemote)
        XCTAssertFalse(remoteInfos.contains { $0.name == "feature/pushed" })
    }

    func testPushAndDeleteRemoteBranchAsync() async throws {
        let repoURL = try prepareRepoWithClonedRemote(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        var pushSucceeded = false
        var pushError: String?
        for _ in 0 ..< 5 {
            let pushResult = await gitManager.pushBranchToRemoteAsync(branchName: "feature/to-push")
            if case .success = pushResult {
                pushSucceeded = true
                break
            } else if case let .failure(error) = pushResult {
                pushError = error.localizedDescription
                usleep(50000)
            }
        }
        XCTAssertTrue(pushSucceeded, "Push to local remote should succeed (last error: \(pushError ?? "none"))")

        let remoteBranches = await gitManager.fetchRemoteBranchesAsync()
        XCTAssertTrue(
            remoteBranches.contains("feature/to-push"),
            "Expected remote branch after push, got: \(remoteBranches)"
        )

        var deleteSucceeded = false
        var deleteError: String?
        for _ in 0 ..< 5 {
            let deleteResult = await gitManager.deleteRemoteBranchAsync(branchName: "feature/to-push")
            if case .success = deleteResult {
                deleteSucceeded = true
                break
            } else if case let .failure(error) = deleteResult {
                deleteError = error.localizedDescription
                usleep(50000)
            }
        }
        XCTAssertTrue(deleteSucceeded, "Remote delete should succeed (last error: \(deleteError ?? "none"))")

        try runGit(["fetch", "--prune", "origin"], in: repoURL)

        let remoteBranchesAfter = await gitManager.fetchRemoteBranchesAsync()
        XCTAssertFalse(
            remoteBranchesAfter.contains("feature/to-push"),
            "Expected remote branch gone after delete, got: \(remoteBranchesAfter)"
        )
    }

    func testBranchInfoModelProperties() {
        let local = BranchInfo(
            name: "feature/x",
            isLocal: true,
            isRemote: false,
            isCurrent: true,
            trackingStatus: .ahead(2),
            lastCommitDate: nil
        )
        XCTAssertEqual(local.id, "local/feature/x")
        XCTAssertEqual(local.displayName, "feature/x")

        let remote = BranchInfo(
            name: "feature/x",
            isLocal: false,
            isRemote: true,
            isCurrent: false,
            trackingStatus: .noRemote,
            lastCommitDate: nil
        )
        XCTAssertEqual(remote.id, "remote/feature/x")
        XCTAssertEqual(remote.displayName, "origin/feature/x")
    }

    func testBranchTrackingStatusDescriptions() {
        XCTAssertEqual(BranchTrackingStatus.upToDate.description, "Up to date")
        XCTAssertEqual(BranchTrackingStatus.ahead(3).description, "Ahead by 3")
        XCTAssertEqual(BranchTrackingStatus.behind(2).description, "Behind by 2")
        XCTAssertEqual(
            BranchTrackingStatus.diverged(ahead: 1, behind: 4).description,
            "Diverged: ahead 1, behind 4"
        )
        XCTAssertEqual(BranchTrackingStatus.noRemote.description, "No upstream")
        XCTAssertEqual(BranchTrackingStatus.unknown.description, "Unknown")
    }

    /// Locks in the facade wiring: branch state computed by `GitBranchService`
    /// must be reflected on `GitManager`'s public branch properties via the
    /// Combine pipe.
    func testBranchServiceStatePipesToManager() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/test"], in: repoURL)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        _ = await gitManager.resolveBranchInfoAsync()

        // Allow the Combine `assign(to:)` pipe a tick to flush.
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(
            gitManager.branchInfos,
            gitManager.branchService.branchInfos,
            "gitManager.branchInfos should mirror branchService.branchInfos after the pipe"
        )
    }
}
