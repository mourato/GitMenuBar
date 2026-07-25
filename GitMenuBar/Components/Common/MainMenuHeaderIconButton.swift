import SwiftUI

/// Compact header icon control shared by repository options and app Settings.
struct MainMenuHeaderIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(WorkbenchTypography.body)
        }
        .workbenchIcon()
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
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
