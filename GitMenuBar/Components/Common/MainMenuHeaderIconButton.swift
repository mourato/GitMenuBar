import SwiftUI

/// Compact header icon control shared by repository options and app Settings.
struct MainMenuHeaderIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(WorkbenchTypography.body)
                .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                        .fill(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .onHover { inside in
            isHovered = inside
        }
    }
}

#Preview("Header Icon Button") {
    HStack(spacing: WorkbenchMetrics.compactSpacing) {
        MainMenuHeaderIconButton(
            systemImage: "ellipsis.circle",
            accessibilityLabel: "Repository options",
            accessibilityHint: "Shows repository visibility and deletion actions.",
            action: {}
        )
        MainMenuHeaderIconButton(
            systemImage: "gearshape",
            accessibilityLabel: "Settings",
            accessibilityHint: "Opens GitMenuBar settings.",
            action: {}
        )
    }
    .padding()
}
