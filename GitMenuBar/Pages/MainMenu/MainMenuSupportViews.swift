import SwiftUI

extension MainMenuView {
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
