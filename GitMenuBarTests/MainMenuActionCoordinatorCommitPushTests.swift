@testable import GitMenuBar
import XCTest

@MainActor
extension MainMenuActionCoordinatorTests {
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
}

@MainActor
private final class RefreshTrackingGitManager: GitManager {
    var refreshCount = 0
    var remoteStatusCount = 0
    private var isTrackingRefreshes = false

    func startTrackingRefreshes() {
        refreshCount = 0
        isTrackingRefreshes = true
    }

    override func refreshAsync(includeReflogHistory _: Bool? = nil) async {
        if isTrackingRefreshes {
            refreshCount += 1
        }
    }

    override func checkRemoteStatusAsync() async {
        remoteStatusCount += 1
        isRemoteAhead = false
    }
}
