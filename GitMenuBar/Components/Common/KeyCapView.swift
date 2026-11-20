import SwiftUI

enum KeyCapMetrics {
    static let side: CGFloat = 18
    static let horizontalPadding: CGFloat = WorkbenchMetrics.microSpacing
    static let cornerRadius: CGFloat = WorkbenchMetrics.microCornerRadius
    static let chipSpacing: CGFloat = 2
}

struct KeyCapView: View {
    let symbol: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.secondary)
            .frame(minWidth: KeyCapMetrics.side, minHeight: KeyCapMetrics.side)
            .padding(.horizontal, KeyCapMetrics.horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: KeyCapMetrics.cornerRadius, style: .continuous)
                    .fill(
                        KeyCapChrome.controlFill(
                            colorScheme: colorScheme,
                            contrast: contrast,
                            reduceTransparency: reduceTransparency
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: KeyCapMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        KeyCapChrome.controlBorder(
                            colorScheme: colorScheme,
                            contrast: contrast,
                            reduceTransparency: reduceTransparency
                        ),
                        lineWidth: 1
                    )
            )
    }
}

struct KeyCapGroupView: View {
    let parts: [String]

    var body: some View {
        HStack(spacing: KeyCapMetrics.chipSpacing) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                KeyCapView(symbol: part)
            }
        }
    }
}

private enum KeyCapChrome {
    static func controlFill(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast,
        reduceTransparency: Bool
    ) -> Color {
        if reduceTransparency {
            return Color(nsColor: .controlBackgroundColor)
        }
        let opacity = contrast == .increased ? 0.18 : 0.11
        return colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.65)
    }

    static func controlBorder(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast,
        reduceTransparency: Bool
    ) -> Color {
        if reduceTransparency {
            return Color(nsColor: .separatorColor)
        }
        let opacity = contrast == .increased ? 0.28 : 0.18
        return colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.8)
    }
}

#Preview("KeyCap Group") {
    VStack(spacing: WorkbenchMetrics.sectionSpacing) {
        KeyCapGroupView(parts: ["⌃", "⌥", "C"])
        KeyCapGroupView(parts: ["⌘", "⇧", "S"])
        KeyCapGroupView(parts: ["⌥", "⌘", "A"])
        KeyCapView(symbol: "R")
    }
    .padding(WorkbenchMetrics.panelPadding)
}
