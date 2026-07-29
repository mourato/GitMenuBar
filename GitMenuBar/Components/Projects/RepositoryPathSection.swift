import SwiftUI

struct RepositoryPathSection: View {
    @Binding var repositoryPath: String
    let onBrowse: () -> Void

    var body: some View {
        TextField("Select repository directory", text: $repositoryPath)
            .textFieldStyle(.roundedBorder)
            .font(WorkbenchTypography.field)

        Button("Browse", action: onBrowse)
            .buttonStyle(.borderless)
            .font(WorkbenchTypography.detail)
            .focusable(false)
    }
}

private struct RepositoryPathSectionPreviewContainer: View {
    @State private var repositoryPath = "/Users/usuario/Documents/Projects/gitmenubar"

    var body: some View {
        Form {
            Section {
                RepositoryPathSection(
                    repositoryPath: $repositoryPath,
                    onBrowse: {}
                )
            } header: {
                SettingsFormSectionHeader(title: "Repository Path", icon: "folder")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 180)
    }
}

#Preview("Repository Path Section") {
    RepositoryPathSectionPreviewContainer()
}
