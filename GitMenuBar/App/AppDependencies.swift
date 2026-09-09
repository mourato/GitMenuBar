import Foundation

/// Owns the long-lived service graph for the menu-bar app shell.
///
/// `StatusBarController` remains responsible for AppKit window/status-item
/// lifecycle; it consumes this graph instead of constructing it inline.
@MainActor
final class AppDependencies {
    let gitManager = GitManager()
    let loginItemManager = LoginItemManager()
    let githubAuthManager: GitHubAuthManager
    let appCommandCenter: AppCommandCenter
    let aiProviderStore = AIProviderStore()
    let aiKeychainStore: any AIAPIKeyStore
    let aiCommitMessageService = AICommitMessageService()
    let shortcutActionBridge = MainMenuShortcutActionBridge()
    let presentationModel = MainMenuPresentationModel()
    let usageQuotaStore: UsageQuotaStore
    let projectMonitor = ProjectMonitorStore()
    let repositorySelectionCoordinator: RepositorySelectionCoordinator

    init(githubAuthManager: GitHubAuthManager, appCommandCenter: AppCommandCenter) {
        self.githubAuthManager = githubAuthManager
        self.appCommandCenter = appCommandCenter

        if AppExecutionContext.usesEphemeralCredentialStores {
            aiKeychainStore = InMemoryAIAPIKeyStore()
        } else {
            aiKeychainStore = CachedAIAPIKeyStore.shared
        }

        usageQuotaStore = UsageQuotaStore(providers: [
            CodexUsageProvider(),
            CursorUsageProvider(),
            OpenRouterUsageProvider(keyStore: aiKeychainStore),
            GeminiUsageProvider(),
            AntigravityUsageProvider()
        ])
        repositorySelectionCoordinator = RepositorySelectionCoordinator(
            gitManager: gitManager,
            projectMonitor: projectMonitor
        )

        gitManager.tokenProvider = { [weak githubAuthManager] in
            githubAuthManager?.storedTokenSnapshot()
        }
        gitManager.githubAPIClient = GitHubAPIClient(authManager: githubAuthManager)
    }

    func makeAICommitCoordinator() -> AICommitCoordinator {
        AICommitCoordinator(
            providerStore: aiProviderStore,
            keychainStore: aiKeychainStore,
            messageService: aiCommitMessageService,
            gitManager: gitManager
        )
    }

    func makeActionCoordinator(
        aiCommitCoordinator: AICommitCoordinator,
        onCommitCompleted: (@MainActor (String) -> Void)? = nil
    ) -> MainMenuActionCoordinator {
        MainMenuActionCoordinator(
            gitManager: gitManager,
            aiCommitCoordinator: aiCommitCoordinator,
            onCommitCompleted: onCommitCompleted
        )
    }

    func makeCommitHistoryEditCoordinator(
        aiCommitCoordinator: AICommitCoordinator
    ) -> CommitHistoryEditCoordinator {
        CommitHistoryEditCoordinator(
            gitManager: gitManager,
            aiCommitCoordinator: aiCommitCoordinator
        )
    }

    func makeProjectCleanupStore(
        onAffectedPaths: @escaping @MainActor ([String]) -> Void
    ) -> ProjectCleanupStore {
        ProjectCleanupStore(
            projectMonitor: projectMonitor,
            onAffectedPaths: onAffectedPaths
        )
    }

    func makeSettingsWindowController(
        aiCommitCoordinator: AICommitCoordinator,
        onSetAutoHideSuspended: @escaping (Bool) -> Void
    ) -> AppSettingsWindowController {
        AppSettingsWindowController(
            gitManager: gitManager,
            loginItemManager: loginItemManager,
            githubAuthManager: githubAuthManager,
            aiProviderStore: aiProviderStore,
            aiCommitCoordinator: aiCommitCoordinator,
            usageQuotaStore: usageQuotaStore,
            onSetAutoHideSuspended: onSetAutoHideSuspended
        )
    }
}
