import SwiftUI

struct MainMenuOverviewSection: View {
    let banner: InlineStatusBanner?
    let onDismissBanner: () -> Void
    let suggestionPath: String?
    let currentRepoPath: String
    let onCreateRepo: (String) -> Void
    let overview: RepositoryOverviewSnapshot
    let onSelectSection: (MainMenuSidePanelSelection) -> Void
    let history: SidePanelHistoryModel?

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
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

            if let suggestionPath, suggestionPath == currentRepoPath {
                createRepoSuggestionBanner(path: suggestionPath)
            }

            if !currentRepoPath.isEmpty {
                RepositoryOverviewView(
                    overview: overview,
                    onSelectSection: onSelectSection
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

    private func createRepoSuggestionBanner(path: String) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
                .foregroundStyle(.orange)

            Text("GitHub remote not found for this repository.")
                .font(WorkbenchTypography.detail)
                .foregroundStyle(.primary)

            Spacer()

            Button("Create Repo") {
                onCreateRepo(path)
            }
            .workbenchGhost()
        }
        .padding(.horizontal, WorkbenchMetrics.panelPadding)
        .padding(.vertical, WorkbenchMetrics.compactSpacing)
        .background(
            WorkbenchPalette.warningFill(contrast: colorSchemeContrast),
            in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
        )
    }
}

#Preview("Overview Section") {
    MainMenuPreviewHarness {
        MainMenuOverviewSection(
            banner: nil,
            onDismissBanner: {},
            suggestionPath: nil,
            currentRepoPath: "/tmp/demo",
            onCreateRepo: { _ in },
            overview: .empty,
            onSelectSection: { _ in },
            history: nil
        )
    }
    .frame(width: 380)
    .padding()
}
