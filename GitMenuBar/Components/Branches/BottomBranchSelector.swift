import AppKit
import SwiftUI

struct BottomBranchSelectorView: View {
    let currentBranch: String
    let commitCount: Int
    let isRemoteAhead: Bool
    let behindCount: Int
    let isDetachedHead: Bool
    let onTap: () -> Void
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Label(currentBranch, systemImage: "arrow.triangle.branch")
                    .font(MacChromeTypography.detail)
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)

                if commitCount > 0 {
                    statusBadge(symbol: "arrow.up", count: commitCount, style: .accent)
                }

                if isRemoteAhead {
                    statusBadge(symbol: "arrow.down", count: behindCount, style: .warning)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
            .animation(nil, value: currentBranch)
            .animation(nil, value: commitCount)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current branch \(currentBranch)")
        .accessibilityHint("Shows branch selection and sync actions.")
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var backgroundColor: Color {
        if isDetachedHead {
            return Color.red.opacity(colorSchemeContrast == .increased ? 0.28 : 0.16)
        }

        return Color(nsColor: .controlBackgroundColor)
    }

    private func statusBadge(symbol: String, count: Int, style: BadgeStyle) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text("\(count)")
        }
        .font(MacChromeTypography.captionStrong)
        .foregroundStyle(style.foregroundColor)
        .padding(.horizontal, 7)
        .frame(minHeight: 20)
        .background(style.backgroundColor(colorSchemeContrast: colorSchemeContrast))
        .clipShape(Capsule())
    }
}

private enum BadgeStyle {
    case accent
    case warning

    var foregroundColor: Color {
        switch self {
        case .accent:
            return .accentColor
        case .warning:
            return .orange
        }
    }

    func backgroundColor(colorSchemeContrast: ColorSchemeContrast) -> Color {
        switch self {
        case .accent:
            return MacChromePalette.accentFill(contrast: colorSchemeContrast)
        case .warning:
            return MacChromePalette.warningFill(contrast: colorSchemeContrast)
        }
    }
}

#Preview("Bottom Branch Selector") {
    BottomBranchSelectorView(
        currentBranch: "main",
        commitCount: 3,
        isRemoteAhead: true,
        behindCount: 1,
        isDetachedHead: false,
        onTap: {}
    )
    .padding()
}
