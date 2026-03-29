import SwiftUI

struct InlineStatusBanner: Equatable {
    enum Style: Equatable {
        case info
        case warning
        case error
    }

    let title: String?
    let message: String
    let style: Style
}

struct InlineStatusBannerView: View {
    let banner: InlineStatusBanner
    let onDismiss: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        HStack(alignment: .top, spacing: MacChromeMetrics.compactSpacing) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let title = banner.title {
                    Text(title)
                        .font(.headline)
                        .fontWeight(legibilityWeight == .bold ? .bold : .semibold)
                }

                Text(banner.message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .accessibilityHint("Clears the current status message.")
        }
        .padding(.horizontal, MacChromeMetrics.panelPadding)
        .padding(.vertical, MacChromeMetrics.compactSpacing)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: MacChromeMetrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MacChromeMetrics.cornerRadius)
                .strokeBorder(borderColor, lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
        )
    }

    private var iconName: String {
        switch banner.style {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch banner.style {
        case .info:
            return .accentColor
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch banner.style {
        case .info:
            return Color(nsColor: .controlBackgroundColor)
        case .warning:
            return MacChromePalette.warningFill(contrast: colorSchemeContrast)
        case .error:
            return MacChromePalette.errorFill(contrast: colorSchemeContrast)
        }
    }

    private var borderColor: Color {
        switch banner.style {
        case .info:
            return Color.secondary.opacity(colorSchemeContrast == .increased ? 0.6 : 0.2)
        case .warning:
            return MacChromePalette.warningBorder(contrast: colorSchemeContrast)
        case .error:
            return MacChromePalette.errorBorder(contrast: colorSchemeContrast)
        }
    }
}

#Preview("Inline Status Banner") {
    InlineStatusBannerView(
        banner: InlineStatusBanner(
            title: "Sync Failed",
            message: "The remote rejected the push because the branch is behind origin/main.",
            style: .error
        ),
        onDismiss: {}
    )
    .padding()
    .frame(width: 380)
}
