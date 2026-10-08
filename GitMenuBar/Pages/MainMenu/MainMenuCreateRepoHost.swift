import SwiftUI

/// Hosts the create-repository route: the repository creation page wired to
/// the presentation model, action coordinator, repository selection, and Git
/// state. Reads only the environment it needs plus the folder path.
struct MainMenuCreateRepoHost: View {
    let folderPath: String

    @Environment(MainMenuPresentationModel.self) private var presentationModel
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator
    @Environment(RepositorySelectionCoordinator.self) private var repositorySelectionCoordinator
    @Environment(GitManager.self) private var gitManager
    @Environment(GitHubAuthManager.self) private var githubAuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CreateRepositoryPageView(
            folderPath: folderPath,
            onCancel: {
                presentationModel.showMain(requestCommitFocus: true)
            },
            onSuccess: { path in
                guard actionCoordinator.canSwitchRepository(to: path) else { return }
                if case .selected = repositorySelectionCoordinator.select(
                    path: path,
                    allowsNonGitSelection: true
                ) {
                    actionCoordinator.resetForRepositorySwitch()
                }
                presentationModel.showMain(requestCommitFocus: true)
                Task { await gitManager.updateRemoteUrlAsync() }
                Task { await gitManager.refreshAsync(includeReflogHistory: false) }
            }
        )
        .environment(gitManager)
        .environment(githubAuthManager)
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
        .padding(.bottom, WorkbenchMetrics.windowPadding)
        .transition(routeTransition)
    }

    private var routeTransition: AnyTransition {
        MainMenuRouteTransition.transition(for: presentationModel.route, reduceMotion: reduceMotion)
    }
}

#Preview("Create Repo Host") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        MainMenuCreateRepoHost(folderPath: "/tmp/example-project")
    }
}
