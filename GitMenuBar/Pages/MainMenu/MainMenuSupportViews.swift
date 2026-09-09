import SwiftUI

extension MainMenuView {
    func createRepoSuggestionBanner(path: String) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text("GitHub remote not found for this repository.")
                .font(WorkbenchTypography.detail)
                .foregroundStyle(.primary)

            Spacer()

            Button("Create Repo") {
                presentationModel.showCreateRepo(path: path)
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
