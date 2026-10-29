@testable import GitMenuBar
import XCTest

@MainActor
final class GitManagerRefreshTests: XCTestCase {
    func testNormalizingEmptyRepositoryPathRemainsEmpty() {
        XCTAssertEqual(GitRepositoryContext.normalizedPath(""), "")
    }

    func testSupersededSelectedRefreshCannotPublishOrFinish() async {
        let manager = GitManager(repositoryPathOverride: "")
        let firstStarted = XCTestExpectation(description: "first refresh starts")
        let secondFinished = XCTestExpectation(description: "second refresh finishes")
        var completions = 0

        manager.selectedRefreshOperation = { [weak manager] session in
            if session.generation == 1 {
                firstStarted.fulfill()
                while !Task.isCancelled {
                    await Task.yield()
                }
                await GitExecution.publishOnMainActor(ifCurrent: session) {
                    manager?.remoteUrl = "A"
                }
                return
            }

            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.remoteUrl = "B"
            }
        }

        manager.refreshSelectedRepository(path: "/tmp/project-a") {
            completions += 1
        }
        await fulfillment(of: [firstStarted])

        await manager.refreshSelectedRepository(path: "/tmp/project-b") {
            completions += 1
            secondFinished.fulfill()
        }
        await fulfillment(of: [secondFinished])

        XCTAssertEqual(manager.remoteUrl, "B")
        XCTAssertEqual(completions, 1)
    }

    func testPullToRefreshTerminatesAndCannotPublishAfterRepositorySwitch() async {
        let manager = GitManager(repositoryPathOverride: "")
        let firstStarted = XCTestExpectation(description: "pull refresh starts")
        let secondFinished = XCTestExpectation(description: "selected refresh finishes")

        manager.selectedRefreshOperation = { [weak manager] session in
            if session.generation == 1 {
                firstStarted.fulfill()
                while !Task.isCancelled {
                    await Task.yield()
                }
                await GitExecution.publishOnMainActor(ifCurrent: session) {
                    manager?.remoteUrl = "A"
                    manager?.currentBranch = "branch-a"
                }
                return
            }

            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.remoteUrl = "B"
                manager?.currentBranch = "branch-b"
            }
            secondFinished.fulfill()
        }

        let pullRefresh = Task { @MainActor in
            await manager.refreshSelectedRepositoryAsync(
                path: "/tmp/project-a",
                includeReflogHistory: false
            )
        }
        await fulfillment(of: [firstStarted])

        await manager.refreshSelectedRepository(path: "/tmp/project-b")
        await fulfillment(of: [secondFinished])
        await pullRefresh.value

        XCTAssertEqual(manager.remoteUrl, "B")
        XCTAssertEqual(manager.currentBranch, "branch-b")
    }

    func testFastCompletionPrecedesFinalCompletionAndKeepsDetailState() async {
        let manager = GitManager(repositoryPathOverride: "")
        let finished = XCTestExpectation(description: "refresh finishes")
        var events: [String] = []

        manager.selectedRefreshOperation = { [weak manager] session in
            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.changedFiles = [WorkingTreeFile(path: "README.md", lineDiff: .zero, status: .modified)]
                manager?.currentBranch = "feature/progressive"
                events.append("fast-state")
            }
            session.fastCompletion()
            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.remoteUrl = "https://github.com/example/project"
                events.append("detail-state")
            }
        }

        await manager.refreshSelectedRepository(
            fastCompletion: { events.append("fast") },
            completion: {
                events.append("final")
                finished.fulfill()
            }
        )
        await fulfillment(of: [finished])

        XCTAssertEqual(events, ["fast-state", "fast", "detail-state", "final"])
        XCTAssertEqual(manager.remoteUrl, "https://github.com/example/project")
    }

    func testStartupWithEmptyPathDoesNotAdvanceGeneration() async {
        let manager = StartupProbeGitManager(repositoryPath: "")
        XCTAssertEqual(manager.refreshCount, 0)
        XCTAssertFalse(manager.refreshCalled)
        XCTAssertEqual(manager.commitCount, 0)
        XCTAssertTrue(manager.availableBranches.isEmpty)

        var observedGeneration: Int?
        manager.selectedRefreshOperation = { session in
            observedGeneration = session.generation
        }
        await manager.refreshSelectedRepositoryAsync(path: "/tmp/project-a")
        XCTAssertEqual(observedGeneration, 1)
    }

    func testStartupWithRepositoryPathReusesSelectedRefreshLifecycle() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let manager = StartupProbeGitManager(repositoryPath: repoURL.path)

        XCTAssertEqual(manager.refreshCount, 1)
        XCTAssertTrue(manager.refreshCalled)
        await manager.awaitStartupRefresh()

        XCTAssertEqual(manager.currentBranch, "main")
        XCTAssertTrue(manager.availableBranches.contains("main"))
        XCTAssertFalse(manager.currentHash.isEmpty)
        XCTAssertEqual(manager.commitCount, 0)
        XCTAssertFalse(manager.commitHistory.isEmpty)
    }

    func testStartupAheadCountUsesSingleBranchServiceSourceOfTruth() async throws {
        let upstreamURL = try createTemporaryGitRepository(testName: "\(#function)_upstream")
        let repoURL = try makeTemporaryTestDirectory(testName: "\(#function)_clone")
        try runGit(["clone", upstreamURL.path, repoURL.path], in: repoURL.deletingLastPathComponent())
        try runGit(["config", "user.email", "test@example.com"], in: repoURL)
        try runGit(["config", "user.name", "GitMenuBar Tests"], in: repoURL)

        try "update 1\n".write(to: repoURL.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "file1.txt"], in: repoURL)
        try runGit(["commit", "-m", "commit 1"], in: repoURL)

        try "update 2\n".write(to: repoURL.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "file2.txt"], in: repoURL)
        try runGit(["commit", "-m", "commit 2"], in: repoURL)

        let manager = StartupProbeGitManager(repositoryPath: repoURL.path)
        await manager.awaitStartupRefresh()

        XCTAssertEqual(manager.commitCount, 2)
        XCTAssertTrue(manager.isAheadOfRemote)
    }

    func testFetchBranchesAsyncSupersessionAtSessionSeam() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "feature/ready"], in: repoURL)
        let manager = GitManager(repositoryPathOverride: "")
        manager.branchService.availableBranches = ["initial"]

        var isCurrent = false
        let supersededSession = GitRefreshSession(
            repositoryPath: repoURL.path,
            generation: 1,
            isCurrent: { isCurrent },
            fastCompletion: {}
        )

        // When session is not current (superseded), availableBranches must not be published
        await manager.branchService.fetchBranchesAsync(session: supersededSession)
        XCTAssertEqual(manager.availableBranches, ["initial"])

        // When session is current, branches must be published deterministically
        isCurrent = true
        let activeSession = GitRefreshSession(
            repositoryPath: repoURL.path,
            generation: 2,
            isCurrent: { isCurrent },
            fastCompletion: {}
        )
        await manager.branchService.fetchBranchesAsync(session: activeSession)
        XCTAssertTrue(manager.availableBranches.contains("feature/ready"))
        XCTAssertTrue(manager.availableBranches.contains("main"))
    }

    func testSupersededSelectedRefreshCannotPublishStaleBranches() async {
        let manager = GitManager(repositoryPathOverride: "")
        let firstStarted = XCTestExpectation(description: "first refresh starts")
        let secondFinished = XCTestExpectation(description: "second refresh finishes")

        manager.selectedRefreshOperation = { [weak manager] session in
            if session.generation == 1 {
                firstStarted.fulfill()
                while !Task.isCancelled {
                    await Task.yield()
                }
                await GitExecution.publishOnMainActor(ifCurrent: session) {
                    manager?.branchService.availableBranches = ["stale-branch"]
                }
                return
            }

            await GitExecution.publishOnMainActor(ifCurrent: session) {
                manager?.branchService.availableBranches = ["fresh-branch"]
            }
            secondFinished.fulfill()
        }

        manager.refreshSelectedRepository(path: "/tmp/project-a")
        await fulfillment(of: [firstStarted])

        await manager.refreshSelectedRepository(path: "/tmp/project-b")
        await fulfillment(of: [secondFinished])

        XCTAssertEqual(manager.availableBranches, ["fresh-branch"])
    }
}

@MainActor
private final class StartupProbeGitManager: GitManager {
    @MainActor
    private final class RefreshCompletion {
        private var didComplete = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            guard !didComplete else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if didComplete {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        }

        func fulfill() {
            didComplete = true
            continuation?.resume()
            continuation = nil
        }
    }

    var refreshCount = 0
    var refreshCalled: Bool {
        refreshCount > 0
    }

    private let startupRefreshCompletion = RefreshCompletion()

    init(repositoryPath: String) {
        super.init(repositoryPathOverride: repositoryPath)
    }

    func awaitStartupRefresh() async {
        await startupRefreshCompletion.wait()
    }

    override func refreshSelectedRepository(
        path: String? = nil,
        includeReflogHistory: Bool? = nil,
        completion: (() -> Void)? = nil
    ) {
        refreshCount += 1
        super.refreshSelectedRepository(path: path, includeReflogHistory: includeReflogHistory) {
            completion?()
            self.startupRefreshCompletion.fulfill()
        }
    }
}
