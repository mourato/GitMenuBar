@testable import GitMenuBar
import XCTest

@MainActor
extension MainMenuActionCoordinatorTests {
    func testReviewedAtomicCommitsStayLocalAndRefreshOnce() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nreviewed-change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)
        guard let snapshot = await gitManager.makeAtomicCommitSnapshotAsync() else {
            return XCTFail("Expected an atomic commit snapshot")
        }

        var refreshedPaths: [String] = []
        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession(),
            onCommitCompleted: { path in refreshedPaths.append(path) }
        )

        let result = await actionCoordinator.performReviewedAtomicCommits(
            plan: AtomicCommitExecutionPlan(
                groups: [AtomicCommitGroup(files: ["README.md"], message: "feat: reviewed commit")],
                snapshot: snapshot
            )
        )

        XCTAssertEqual(result, .committed)
        XCTAssertEqual(refreshedPaths, [repoURL.path])
        XCTAssertNil(actionCoordinator.alert)
        XCTAssertNotNil(actionCoordinator.success)
        XCTAssertFalse(actionCoordinator.showSyncOptions)
        XCTAssertEqual(
            try runGit(["log", "-1", "--pretty=%B"], in: repoURL)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "feat: reviewed commit"
        )
    }
}
