import SwiftUI

struct MainMenuOverviewSection: View {
    let banner: InlineStatusBanner?
    let onDismissBanner: () -> Void
    let currentRepoPath: String
    let overview: RepositoryOverviewSnapshot
    let selection: MainMenuSidePanelSelection?
    let onSelectSection: (MainMenuSidePanelSelection) -> Void
    let history: SidePanelHistoryModel?

    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator
    @State private var pendingReset: Commit?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            if let banner {
                InlineStatusBannerView(
                    banner: banner,
                    onDismiss: onDismissBanner
                )
            }

            if !currentRepoPath.isEmpty {
                RepositoryOverviewView(
                    overview: overview,
                    selection: selection,
                    onSelectSection: onSelectSection,
                    onOpenGitHubPage: { actionCoordinator.openGitHubPage($0) },
                    canOpenGitHubPage: actionCoordinator.canOpenGitHubPage
                )

                if let history {
                    SidePanelHistoryBrowserView(
                        history: history,
                        pendingReset: $pendingReset
                    )
                }
            }
        }
        .sidePanelResetAlert(commit: $pendingReset) { commit in
            Task {
                _ = await actionCoordinator.sidePanel.resetSidePanelCommit(hash: commit.id)
            }
        }
    }
}

#Preview("Overview Section") {
    MainMenuPreviewHarness {
        MainMenuOverviewSection(
            banner: nil,
            onDismissBanner: {},
            currentRepoPath: "/tmp/demo",
            overview: .empty,
            selection: nil,
            onSelectSection: { _ in },
            history: nil
        )
    }
    .frame(width: 380)
    .padding()
}
