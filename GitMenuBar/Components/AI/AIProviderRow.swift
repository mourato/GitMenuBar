import SwiftUI

struct AIProviderRowView: View {
    let provider: AIProviderConfig
    let isDefault: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(provider.name)
                    .font(WorkbenchTypography.detail.weight(.semibold))

                Text("\(provider.type.displayName) · \(provider.selectedModel)")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if isDefault {
                Text("Default")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, WorkbenchMetrics.chipSpacing)
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
                    .background(
                        WorkbenchPalette.accentFill(contrast: colorSchemeContrast),
                        in: Capsule()
                    )
            }

            Button("Edit \(provider.name)", action: onEdit)
                .buttonStyle(.borderless)
                .font(.caption)
                .accessibilityLabel("Edit \(provider.name)")

            Button("Delete \(provider.name)", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityLabel("Delete \(provider.name)")
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.chipSpacing)
    }
}

#Preview("AI Provider Row") {
    AIProviderRowView(
        provider: AIProviderConfig(
            name: "OpenAI Primary",
            type: .openAI,
            endpointURL: "https://api.openai.com",
            selectedModel: "gpt-5",
            availableModels: ["gpt-5"]
        ),
        isDefault: true,
        onEdit: {},
        onDelete: {}
    )
    .padding()
    .frame(width: 420)
}
