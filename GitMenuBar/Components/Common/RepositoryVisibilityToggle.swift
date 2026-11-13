import SwiftUI

struct RepositoryVisibilityToggle: View {
    @Binding var isPrivate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            SettingsFormSectionHeader(
                title: "Visibility",
                icon: isPrivate ? .lock : .globe
            )

            Picker("Visibility", selection: $isPrivate) {
                Label(lucide: .globe, "Public")
                    .tag(false)
                Label(lucide: .lock, "Private")
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
