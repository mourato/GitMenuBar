import SwiftUI

/// Owns the single native grouped Form and its vertical scrolling for a settings page.
struct SettingsFormPage<Content: View>: View {
    private let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(
                minWidth: SettingsFormLayoutPolicy.contentWidth(availableWidth: geometry.size.width),
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .workbenchScrollbarStyle()
        }
    }
}

#Preview("Settings Form Page — 560") {
    SettingsFormPage {
        Section("Workflow") {
            Picker("Confirmation delay", selection: .constant(6)) {
                Text("6 seconds").tag(6)
                Text("10 seconds").tag(10)
            }
            .pickerStyle(.menu)
            Toggle("Automatically start recording", isOn: .constant(true))
                .toggleStyle(.switch)
        }
        Section("Details") {
            Text("Long help text wraps inside the native section without introducing another scroll owner.")
                .foregroundStyle(.secondary)
                .font(WorkbenchTypography.caption)
        }
    }
    .frame(width: 560, height: 360)
}

#Preview("Settings Form Page — 600") {
    SettingsFormPage {
        Section("Workflow") {
            Toggle("Automatically start recording", isOn: .constant(true))
                .toggleStyle(.switch)
        }
        Section("Details") {
            Text("A standard-width native grouped Form.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
        }
    }
    .frame(width: 600, height: 300)
}
