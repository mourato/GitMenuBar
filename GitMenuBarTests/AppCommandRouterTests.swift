@testable import GitMenuBar
import XCTest

@MainActor
final class AppCommandRouterTests: XCTestCase {
    func testSyncInvocationPresentsCoordinatorSyncOptionsWhenDiverged() async throws {
        let defaults = try makeIsolatedTestDefaults(name: #function)
        let gitManager = GitManager(repositoryPathOverride: "")
        gitManager.isRemoteAhead = true
        gitManager.isAheadOfRemote = true
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
            refreshAppCommands: { XCTFail("Unexpected command refresh") }
        )

        router.performAppCommand(.command(.sync))
        await fulfillment(of: [feedback], timeout: 1)

        XCTAssertTrue(coordinator.showSyncOptions)
        XCTAssertNil(coordinator.alert)
        XCTAssertFalse(coordinator.isExecutingPrimaryAction)
    }

    func testSyncInvocationSkipsOptionsWhenBehindOnly() async {
        let gitManager = GitManager(repositoryPathOverride: "")
        gitManager.isRemoteAhead = true
        gitManager.isAheadOfRemote = false
        let aiCoordinator = AICommitCoordinator(
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            keychainStore: InMemoryAIAPIKeyStore(),
            messageService: AICommitMessageService(),
            gitManager: gitManager
        )
        let coordinator = MainMenuActionCoordinator(gitManager: gitManager, aiCommitCoordinator: aiCoordinator)

        let result = await coordinator.performSync()

        XCTAssertEqual(result, .failed)
        XCTAssertFalse(coordinator.showSyncOptions)
        XCTAssertFalse(coordinator.isExecutingPrimaryAction)
    }
}
