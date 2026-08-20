@testable import GitMenuBar
import XCTest

@MainActor
extension MainMenuActionCoordinatorTests {
    func testLocalCommitStillPerformsTerminalRefresh() async throws {
        let localRepoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = localRepoURL.appendingPathComponent("README.md")
        try "base\nlocal change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = RefreshTrackingGitManager(repositoryPathOverride: localRepoURL.path)
        await waitForWorkingTreeUpdate(gitManager)
        gitManager.startTrackingRefreshes()

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.performCommit(commentText: "feat: local change")

        XCTAssertEqual(result, .committed)
        XCTAssertEqual(gitManager.refreshCount, 1)
        XCTAssertEqual(gitManager.remoteStatusCount, 1)
    }

    func testCommitAndPushRefreshesLocallyOnlyAfterPush() async throws {
        let remoteDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMenuBarTests")
            .appendingPathComponent(#function + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: remoteDirectory, withIntermediateDirectories: true)

        let remoteURL = remoteDirectory.appendingPathComponent("origin.git")
        try runGit(["init", "--bare", remoteURL.path], in: remoteDirectory)

        let localRepoURL = try createTemporaryGitRepository(testName: #function + "-local")
        try runGit(["remote", "add", "origin", remoteURL.path], in: localRepoURL)
        try runGit(["push", "-u", "origin", "HEAD"], in: localRepoURL)

        let fileURL = localRepoURL.appendingPathComponent("README.md")
        try "base\nlocal change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = RefreshTrackingGitManager(repositoryPathOverride: localRepoURL.path)
        await waitForWorkingTreeUpdate(gitManager)
        gitManager.startTrackingRefreshes()

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.performCommit(
            commentText: "feat: local change",
            shouldPushAfterCommit: true
        )

        XCTAssertEqual(result, .committed)
        XCTAssertEqual(gitManager.refreshCount, 1)
        XCTAssertEqual(gitManager.remoteStatusCount, 2)
        let remoteMessage = try runGit(
            ["--git-dir", remoteURL.path, "log", "-1", "--pretty=%B"],
            in: remoteDirectory
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(remoteMessage, "feat: local change")
    }

    func testRemoteAheadCommitRefreshesBeforeShowingSyncOptions() async throws {
        let localRepoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = localRepoURL.appendingPathComponent("README.md")
        try "base\nlocal change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = RefreshTrackingGitManager(repositoryPathOverride: localRepoURL.path)
        await waitForWorkingTreeUpdate(gitManager)
        gitManager.remoteAhead = true
        gitManager.startTrackingRefreshes()

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.performCommit(
            commentText: "feat: local change",
            shouldPushAfterCommit: true
        )

        XCTAssertEqual(result, .committedAndNeedsSyncOptions)
        XCTAssertTrue(actionCoordinator.showSyncOptions)
        XCTAssertEqual(gitManager.refreshCount, 1)
        XCTAssertEqual(gitManager.pushCount, 0)
    }

    func testPushFailureRefreshesTheLocalCommitBeforeReturning() async throws {
        let localRepoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = localRepoURL.appendingPathComponent("README.md")
        try "base\nlocal change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = RefreshTrackingGitManager(repositoryPathOverride: localRepoURL.path)
        await waitForWorkingTreeUpdate(gitManager)
        gitManager.forcedPushResult = .failure(
            NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "push failed"])
        )
        gitManager.startTrackingRefreshes()

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.performCommit(
            commentText: "feat: local change",
            shouldPushAfterCommit: true
        )

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(gitManager.refreshCount, 1)
        XCTAssertEqual(gitManager.pushCount, 1)
        XCTAssertTrue(actionCoordinator.alert?.message.contains("created locally") == true)
        let headMessage = try runGit(["log", "-1", "--pretty=%B"], in: localRepoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(headMessage, "feat: local change")
    }
}

@MainActor
private final class RefreshTrackingGitManager: GitManager {
    var refreshCount = 0
    var remoteStatusCount = 0
    var pushCount = 0
    var remoteAhead = false
    var forcedPushResult: Result<Void, Error>?
    private var isTrackingRefreshes = false

    func startTrackingRefreshes() {
        refreshCount = 0
        remoteStatusCount = 0
        pushCount = 0
        isTrackingRefreshes = true
    }

    override func refreshAsync(includeReflogHistory _: Bool? = nil) async {
        if isTrackingRefreshes {
            refreshCount += 1
        }
    }

    override func checkRemoteStatusAsync() async {
        remoteStatusCount += 1
        isRemoteAhead = remoteAhead
    }

    override func pushToRemoteAsync() async -> Result<Void, Error> {
        pushCount += 1
        if let forcedPushResult {
            return forcedPushResult
        }
        return await super.pushToRemoteAsync()
    }
}
