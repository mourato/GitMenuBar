import SwiftUI

struct RepositoryPathSection: View {
    @Binding var repositoryPath: String
    let onBrowse: () -> Void

    var body: some View {
        SettingsSection(title: "Git Repository Path", systemImage: "folder") {
            TextField("Select repository directory", text: $repositoryPath)
                .textFieldStyle(.roundedBorder)
                .font(MacChromeTypography.field)

            Button("Browse...", action: onBrowse)
                .buttonStyle(.borderless)
                .font(MacChromeTypography.detail)
                .focusable(false)
        }
    }
}

private struct RepositoryPathSectionPreviewContainer: View {
    @State private var repositoryPath = "/Users/usuario/Documents/Projects/gitmenubar"

    var body: some View {
        RepositoryPathSection(
            repositoryPath: $repositoryPath,
            onBrowse: {}
        )
        .padding()
        .frame(width: 360)
    }
}

#Preview("Repository Path Section") {
    RepositoryPathSectionPreviewContainer()
}
