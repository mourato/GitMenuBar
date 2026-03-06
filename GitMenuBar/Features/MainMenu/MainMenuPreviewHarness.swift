import SwiftUI

struct MainMenuPreviewHarness<Content: View>: View {
    @StateObject private var gitManager: GitManager
    @StateObject private var loginItemManager = LoginItemManager()
    @StateObject private var githubAuthManager: GitHubAuthManager
    @StateObject private var aiProviderStore: AIProviderStore
    @StateObject private var aiCommitCoordinator: AICommitCoordinator
    @StateObject private var shortcutActionBridge = MainMenuShortcutActionBridge()

    private let width: CGFloat
    private let content: Content

    init(width: CGFloat = 400, @ViewBuilder content: () -> Content) {
        let previewGitManager = GitManager(repositoryPathOverride: NSHomeDirectory())
        let previewGitHubAuthManager = GitHubAuthManager(
            tokenStore: InMemoryGitHubTokenStore(),
            preloadStoredToken: false
        )
        let previewProviderStore = AIProviderStore()
        let previewKeychainStore = InMemoryAIAPIKeyStore()
        let previewCoordinator = AICommitCoordinator(
            providerStore: previewProviderStore,
            keychainStore: previewKeychainStore,
            messageService: AICommitMessageService(),
            gitManager: previewGitManager
        )

        _gitManager = StateObject(wrappedValue: previewGitManager)
        _githubAuthManager = StateObject(wrappedValue: previewGitHubAuthManager)
        _aiProviderStore = StateObject(wrappedValue: previewProviderStore)
        _aiCommitCoordinator = StateObject(wrappedValue: previewCoordinator)

        self.width = width
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(gitManager)
            .environmentObject(loginItemManager)
            .environmentObject(githubAuthManager)
            .environmentObject(aiProviderStore)
            .environmentObject(aiCommitCoordinator)
            .environmentObject(shortcutActionBridge)
            .frame(width: width)
    }
}

#Preview("Preview Harness") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
