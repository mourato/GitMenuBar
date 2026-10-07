import SwiftUI

struct MainMenuPreviewHarness<Content: View>: View {
    @State private var gitManager: GitManager
    @State private var loginItemManager = LoginItemManager()
    @StateObject private var githubAuthManager: GitHubAuthManager
    @StateObject private var aiProviderStore: AIProviderStore
    @StateObject private var aiCommitCoordinator: AICommitCoordinator
    @State private var actionCoordinator: MainMenuActionCoordinator
    @State private var commitHistoryEditCoordinator: CommitHistoryEditCoordinator
    @State private var shortcutActionBridge = MainMenuShortcutActionBridge()
    @State private var presentationModel = MainMenuPresentationModel()
    @StateObject private var usageQuotaStore = UsageQuotaStore()
    @State private var projectMonitor: ProjectMonitorStore
    @State private var repositorySelectionCoordinator: RepositorySelectionCoordinator

    private let width: CGFloat
    private let showsTransparentTitlebar: Bool
    private let content: Content

    init(
        width: CGFloat = 400,
        showsTransparentTitlebar: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        let previewGitManager = GitManager(repositoryPathOverride: NSHomeDirectory())
        let previewProjectMonitor = ProjectMonitorStore()
        #if DEBUG
            let previewGitHubAuthManager = GitHubAuthManager(
                tokenStore: InMemoryGitHubTokenStore(),
                preloadStoredToken: false
            )
            let previewProviderStore = AIProviderStore()
            let previewKeychainStore = InMemoryAIAPIKeyStore()
        #else
            let previewGitHubAuthManager = GitHubAuthManager()
            let previewProviderStore = AIProviderStore()
            let previewKeychainStore = AIKeychainStore()
        #endif
        let previewCoordinator = AICommitCoordinator(
            providerStore: previewProviderStore,
            keychainStore: previewKeychainStore,
            messageService: AICommitMessageService(),
            gitManager: previewGitManager
        )

        _gitManager = State(wrappedValue: previewGitManager)
        _projectMonitor = State(wrappedValue: previewProjectMonitor)
        _repositorySelectionCoordinator = State(
            wrappedValue: RepositorySelectionCoordinator(
                gitManager: previewGitManager,
                projectMonitor: previewProjectMonitor
            )
        )
        _githubAuthManager = StateObject(wrappedValue: previewGitHubAuthManager)
        _aiProviderStore = StateObject(wrappedValue: previewProviderStore)
        _aiCommitCoordinator = StateObject(wrappedValue: previewCoordinator)
        _actionCoordinator = State(
            wrappedValue: MainMenuActionCoordinator(
                gitManager: previewGitManager,
                aiCommitCoordinator: previewCoordinator
            )
        )
        _commitHistoryEditCoordinator = State(
            wrappedValue: CommitHistoryEditCoordinator(
                gitManager: previewGitManager,
                aiCommitCoordinator: previewCoordinator
            )
        )

        self.width = width
        self.showsTransparentTitlebar = showsTransparentTitlebar
        self.content = content()
    }

    var body: some View {
        content
            .environment(gitManager)
            .environment(loginItemManager)
            .environmentObject(githubAuthManager)
            .environmentObject(aiProviderStore)
            .environmentObject(aiCommitCoordinator)
            .environment(actionCoordinator)
            .environment(commitHistoryEditCoordinator)
            .environment(shortcutActionBridge)
            .environment(presentationModel)
            .environmentObject(usageQuotaStore)
            .environment(projectMonitor)
            .environment(repositorySelectionCoordinator)
            .frame(width: width)
            .modifier(TransparentTitlebarPreviewChrome(isVisible: showsTransparentTitlebar))
    }
}

#Preview("Preview Harness") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        MainMenuView()
    }
}

private struct TransparentTitlebarPreviewChrome: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .padding(.top, isVisible ? WorkbenchMetrics.iconHitTarget : 0)
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.largeCornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if isVisible {
                    previewTrafficLights
                        .padding(.leading, 20)
                        .frame(height: WorkbenchMetrics.iconHitTarget, alignment: .center)
                        .allowsHitTesting(false)
                }
            }
    }

    private var previewTrafficLights: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 1.0, green: 0.36, blue: 0.32))
            Circle()
                .fill(Color(red: 1.0, green: 0.75, blue: 0.18))
            Circle()
                .fill(Color(red: 0.22, green: 0.80, blue: 0.33))
        }
        .frame(width: 52, height: 12)
        .accessibilityHidden(true)
    }
}
