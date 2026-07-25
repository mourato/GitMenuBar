import SwiftUI

/// A native Form Section header with shared Settings icon and title anatomy.
struct SettingsFormSectionHeader<Accessory: View>: View {
    private let title: String
    private let icon: String?
    private let accessory: Accessory

    init(
        title: String,
        icon: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.icon = icon
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsFormSectionHeader where Accessory == EmptyView {
    init(title: String, icon: String? = nil) {
        self.init(title: title, icon: icon) { EmptyView() }
    }
}

#Preview("Settings Form Section Header") {
    Form {
        Section {
            Text("Native grouped Form content")
                .font(WorkbenchTypography.body)
        } header: {
            SettingsFormSectionHeader(title: "Workflow", icon: "bolt.fill") {
                Text("Optional")
                    .foregroundStyle(.secondary)
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 180)
}
