import Foundation

@MainActor
final class AppDependencies {
    let gitManager = GitManager()
    let loginItemManager = LoginItemManager()
    let appCommandCenter: AppCommandCenter
    let aiProviderStore = AIProviderStore()
    let aiKeychainStore: any AIAPIKeyStore
    let chatGPTSubscription = ChatGPTSubscriptionManager()
    let aiCommitMessageService: AICommitMessageService
    let shortcutManager = GlobalShortcutManager()
    let shortcutActionBridge = MainMenuShortcutActionBridge()
    let presentationModel = MainMenuPresentationModel()
    let usageQuotaStore: UsageQuotaStore
    let usageQuotaPresentationPreferences: UsageQuotaPresentationPreferences
    let projectMonitor = ProjectMonitorStore()
    let repositorySelectionCoordinator: RepositorySelectionCoordinator

    init(appCommandCenter: AppCommandCenter) {
        self.appCommandCenter = appCommandCenter

        #if DEBUG
            if AppExecutionContext.usesEphemeralCredentialStores {
                aiKeychainStore = InMemoryAIAPIKeyStore()
            } else {
                aiKeychainStore = AIKeychainStore()
            }
        #else
            aiKeychainStore = AIKeychainStore()
        #endif
        aiCommitMessageService = AICommitMessageService(chatGPTGenerator: chatGPTSubscription)
        if aiProviderStore.preferences.chatGPTEnabled {
            _ = chatGPTSubscription.refresh()
        }

        usageQuotaPresentationPreferences = UsageQuotaPresentationPreferences(keyStore: aiKeychainStore)
        usageQuotaStore = UsageQuotaStore(providers: [
            ClaudeCodeUsageProvider(),
            CodexUsageProvider(),
            CursorUsageProvider(),
            OpenRouterUsageProvider(keyStore: aiKeychainStore),
            GeminiUsageProvider(),
            AntigravityUsageProvider(),
            OpenCodeGoUsageProvider(keyStore: aiKeychainStore)
        ])
        repositorySelectionCoordinator = RepositorySelectionCoordinator(
            gitManager: gitManager,
            projectMonitor: projectMonitor
        )
    }

    func makeAICommitCoordinator() -> AICommitCoordinator {
        AICommitCoordinator(
            providerStore: aiProviderStore,
            keychainStore: aiKeychainStore,
            messageService: aiCommitMessageService,
            gitManager: gitManager,
            chatGPTSubscription: chatGPTSubscription
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
        onFetchNow: @escaping () -> Void
    ) -> AppSettingsWindowController {
        AppSettingsWindowController(
            loginItemManager: loginItemManager,
            aiProviderStore: aiProviderStore,
            aiCommitCoordinator: aiCommitCoordinator,
            chatGPTSubscription: chatGPTSubscription,
            usageQuotaStore: usageQuotaStore,
            usageQuotaPresentationPreferences: usageQuotaPresentationPreferences,
            shortcutManager: shortcutManager,
            onFetchNow: onFetchNow
        )
    }
}
