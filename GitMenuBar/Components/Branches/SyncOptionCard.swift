import SwiftUI

enum SyncOptionTone {
    case accent
    case warning
    case success
}

struct SyncOptionCard: View {
    let title: String
    let subtitle: String
    let tone: SyncOptionTone
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(MacChromeMetrics.compactSpacing)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private var backgroundColor: Color {
        switch tone {
        case .accent:
            return MacChromePalette.accentFill(contrast: colorSchemeContrast)
        case .warning:
            return MacChromePalette.warningFill(contrast: colorSchemeContrast)
        case .success:
            return MacChromePalette.successFill(contrast: colorSchemeContrast)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .accent:
            return Color.accentColor.opacity(colorSchemeContrast == .increased ? 0.65 : 0.25)
        case .warning:
            return MacChromePalette.warningBorder(contrast: colorSchemeContrast)
        case .success:
            return Color.green.opacity(colorSchemeContrast == .increased ? 0.65 : 0.3)
        }
    }
}

#Preview("Sync Option Card") {
    SyncOptionCard(
        title: "Pull and Rebase",
        subtitle: "Replay local commits on top of origin/main",
        tone: .accent,
        action: {}
    )
    .padding()
    .frame(width: 320)
}
