import SwiftUI

struct MainMenuOverviewSection: View {
    let banner: InlineStatusBanner?
    let onDismissBanner: () -> Void
    let suggestionPath: String?
    let currentRepoPath: String
    let onCreateRepo: (String) -> Void
    let overview: RepositoryOverviewSnapshot
    let commitActionTitle: String
    let canCommit: Bool
    let onCommit: () -> Void
    let canSync: Bool
    let onSync: () -> Void
    let onSelectSection: (MainMenuSidePanelSelection) -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
                    onSelectSection: onSelectSection,
                    commitActionTitle: commitActionTitle,
                    canCommit: canCommit,
                    onCommit: onCommit,
                    canSync: canSync,
                    onSync: onSync
                )
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
    MainMenuOverviewSection(
        banner: nil,
        onDismissBanner: {},
        suggestionPath: nil,
        currentRepoPath: "/tmp/demo",
        onCreateRepo: { _ in },
        overview: .empty,
        commitActionTitle: "Commit",
        canCommit: false,
        onCommit: {},
        canSync: false,
        onSync: {},
        onSelectSection: { _ in }
    )
    .frame(width: 380)
    .padding()
}
