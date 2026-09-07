import SwiftUI

/// Shared side-panel title block: project name, active selection title, close.
struct SidePanelHeaderView: View {
    let projectName: String
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: WorkbenchMetrics.compactSpacing) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(projectName)
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(title)
                    .font(WorkbenchTypography.windowTitle)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close details")
            .accessibilityLabel("Close details")
        }
    }
}

#Preview("Side Panel Header") {
    SidePanelHeaderView(
        projectName: "GitMenuBar",
        title: "Working Tree",
        onClose: {}
    )
    .frame(width: WorkbenchMetrics.sidePanelWidth)
    .padding()
}
