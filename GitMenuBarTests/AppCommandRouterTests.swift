@testable import GitMenuBar
import XCTest

@MainActor
final class AppCommandRouterTests: XCTestCase {
    func testSyncInvocationPresentsCoordinatorSyncOptionsWhenRemoteIsAhead() async throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let gitManager = GitManager(repositoryPathOverride: "")
        gitManager.isRemoteAhead = true
        let aiCoordinator = AICommitCoordinator(
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            keychainStore: InMemoryAIAPIKeyStore(),
            messageService: AICommitMessageService(),
            gitManager: gitManager
        )
        let coordinator = MainMenuActionCoordinator(gitManager: gitManager, aiCommitCoordinator: aiCoordinator)
        let monitor = ProjectMonitorStore(projectStore: MonitoredProjectsStore(defaults: defaults))
        let feedback = expectation(description: "sync options feedback")
        let router = AppCommandRouter(
            gitManager: gitManager,
            githubAuthManager: GitHubAuthManager(tokenStore: InMemoryGitHubTokenStore(), preloadStoredToken: false),
            actionCoordinator: coordinator,
            repositorySelectionCoordinator: RepositorySelectionCoordinator(
                gitManager: gitManager,
                projectMonitor: monitor,
                defaults: defaults
            ),
            projectMonitor: monitor,
            presentationModel: MainMenuPresentationModel(),
            mainWindowController: { fatalError("Sync options must use feedback callback") },
            openMainWindow: { XCTFail("Unexpected window command") },
            openSettingsWindow: { XCTFail("Unexpected settings command") },
            handleCommandPaletteShortcut: { XCTFail("Unexpected palette command") },
            presentMainWindowForActionFeedback: { feedback.fulfill() },
            openMainWindowWithCreateRepo: { _ in XCTFail("Unexpected repository creation") },
            refreshAppCommands: { XCTFail("Unexpected command refresh") },
            openMainWindowForRoute: { _, _, _, _, _ in XCTFail("Unexpected route presentation") }
        )

        router.performAppCommand(.command(.sync))
        await fulfillment(of: [feedback], timeout: 1)

        XCTAssertTrue(coordinator.showSyncOptions)
        XCTAssertNil(coordinator.alert)
        XCTAssertFalse(coordinator.isExecutingPrimaryAction)
    }
}
