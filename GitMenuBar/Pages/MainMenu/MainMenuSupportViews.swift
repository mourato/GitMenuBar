import SwiftUI

extension MainMenuView {
    var loadingStateView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Loading working tree…")
                .font(MacChromeTypography.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    func createRepoSuggestionBanner(path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text("GitHub remote not found for this repository.")
                .font(MacChromeTypography.detail)
                .foregroundColor(.primary)

            Spacer()

            Button("Create Repo") {
                presentationModel.showCreateRepo(path: path)
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }
}
