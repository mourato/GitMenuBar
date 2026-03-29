import SwiftUI

struct RepositoryVisibilityToggle: View {
    @Binding var isPrivate: Bool

    var body: some View {
        SettingsSection(title: "Visibility", systemImage: isPrivate ? "lock" : "globe") {
            Picker("Visibility", selection: $isPrivate) {
                Label("Public", systemImage: "globe")
                    .tag(false)
                Label("Private", systemImage: "lock")
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Repository visibility")
        }
    }
}

private struct RepoVisibilityPreview: View {
    @State private var isPrivate = true

    var body: some View {
        RepositoryVisibilityToggle(isPrivate: $isPrivate)
            .padding()
            .frame(width: 320)
    }
}

#Preview("Repository Visibility") {
    RepoVisibilityPreview()
}
