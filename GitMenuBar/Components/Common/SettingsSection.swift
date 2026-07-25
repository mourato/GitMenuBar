import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(WorkbenchTypography.detail)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(WorkbenchTypography.sectionLabel)
            }
            .padding(.top, 4)

            content()
        }
    }
}

#Preview("Settings Section") {
    SettingsSection(title: "Preview Section", systemImage: "slider.horizontal.3") {
        Text("Example content")
            .font(WorkbenchTypography.caption)
            .foregroundColor(.secondary)
    }
    .padding()
    .frame(width: 320)
}
