import SwiftUI

struct AIProviderRowView: View {
    let provider: AIProviderConfig
    let isDefault: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.caption.weight(.semibold))

                Text("\(provider.type.displayName) · \(provider.selectedModel)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if isDefault {
                Text("Default")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }

            Button("Edit", action: onEdit)
                .buttonStyle(.borderless)
                .font(.caption)
                .focusable(false)

            Button("Delete", action: onDelete)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.red)
                .focusable(false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(6)
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
