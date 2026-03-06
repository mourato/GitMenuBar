//
//  MainMenuView+Preview.swift
//  GitMenuBar
//

import SwiftUI

private struct MainMenuViewPreviewContainer: View {
    @StateObject private var gitManager: GitManager
    @StateObject private var loginItemManager = LoginItemManager()
    @StateObject private var githubAuthManager = GitHubAuthManager()
    @StateObject private var aiProviderStore = AIProviderStore()
    @StateObject private var aiCommitCoordinator: AICommitCoordinator
    @StateObject private var shortcutActionBridge = MainMenuShortcutActionBridge()

    init() {
        let previewGitManager = GitManager(repositoryPathOverride: NSHomeDirectory())
        let previewProviderStore = AIProviderStore()
        let previewKeychainStore = AIKeychainStore()
        let previewCoordinator = AICommitCoordinator(
            providerStore: previewProviderStore,
            keychainStore: previewKeychainStore,
            messageService: AICommitMessageService(),
            gitManager: previewGitManager
        )

        _gitManager = StateObject(wrappedValue: previewGitManager)
        _aiProviderStore = StateObject(wrappedValue: previewProviderStore)
        _aiCommitCoordinator = StateObject(wrappedValue: previewCoordinator)
    }

    var body: some View {
        MainMenuView()
            .environmentObject(gitManager)
            .environmentObject(loginItemManager)
            .environmentObject(githubAuthManager)
            .environmentObject(aiProviderStore)
            .environmentObject(aiCommitCoordinator)
            .environmentObject(shortcutActionBridge)
            .frame(width: 400)
    }
}

#Preview("Main Menu") {
    MainMenuViewPreviewContainer()
}
