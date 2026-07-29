import AppKit
import SwiftUI

struct BottomBranchSelectorView: View {
    let currentBranch: String
    let commitCount: Int
    let isRemoteAhead: Bool
    let behindCount: Int
    let isDetachedHead: Bool
    let isPresented: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Label(currentBranch, systemImage: "arrow.triangle.branch")
                    .font(WorkbenchTypography.detail)
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)

                if commitCount > 0 {
                    statusBadge(symbol: "arrow.up", count: commitCount, style: .accent)
                }

                if isRemoteAhead {
                    statusBadge(symbol: "arrow.down", count: behindCount, style: .warning)
                }

                Image(systemName: "chevron.down")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: WorkbenchMetrics.iconHitTarget)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                value: currentBranch
            )
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                value: commitCount
            )
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                value: isRemoteAhead
            )
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                value: behindCount
            )
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
                value: isHovered
            )
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
                value: isPresented
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Current branch \(currentBranch)")
        .accessibilityValue(isPresented ? "Branch selector open" : "Branch selector closed")
        .accessibilityHint("Shows branch selection and sync actions.")
        .onHover { inside in
            isHovered = inside
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

        if isPresented {
            return WorkbenchPalette.selectedFill()
        }

        if isHovered {
            return WorkbenchPalette.hoverFill()
        }

        return .clear
    }

    private var borderColor: Color {
        if isDetachedHead {
            return WorkbenchPalette.errorBorder(contrast: colorSchemeContrast)
        }

        if isPresented || isHovered {
            return WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast).opacity(0.55)
        }

        return .clear
    }

    private func statusBadge(symbol: String, count: Int, style: BadgeStyle) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            Text("\(count)")
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .font(WorkbenchTypography.captionStrong)
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
            return WorkbenchPalette.accentFill(contrast: colorSchemeContrast)
        case .warning:
            return WorkbenchPalette.warningFill(contrast: colorSchemeContrast)
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
        isPresented: false,
        onTap: {}
    )
    .padding()
}
