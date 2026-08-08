import SwiftUI

extension MainMenuView {
    var loadingStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([0, 1, 2], id: \.self) { index in
                RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius)
                    .fill(Color.secondary.opacity(index == 0 ? 0.18 : 0.12))
                    .frame(height: 32)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading working tree")
        .accessibilityAddTraits(.updatesFrequently)
    }

    var branchLoadingStateView: some View {
        HStack {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 150, height: WorkbenchMetrics.iconHitTarget)
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)

            Spacer()

            RoundedRectangle(cornerRadius: WorkbenchMetrics.microCornerRadius)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 72, height: WorkbenchMetrics.iconHitTarget)
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading branch")
        .accessibilityAddTraits(.updatesFrequently)
    }

    func createRepoSuggestionBanner(path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text("GitHub remote not found for this repository.")
                .font(WorkbenchTypography.detail)
                .foregroundColor(.primary)

            Spacer()

            Button("Create Repo") {
                presentationModel.showCreateRepo(path: path)
            }
            .workbenchGhost()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }
}
