import SwiftUI

/// Shared side-panel title block: project name, active selection title, close.
struct SidePanelHeaderView: View {
    let projectName: String
    let title: String
    let onClose: () -> Void
    let onStash: (() -> Void)?

    init(
        projectName: String,
        title: String,
        onClose: @escaping () -> Void,
        onStash: (() -> Void)? = nil
    ) {
        self.projectName = projectName
        self.title = title
        self.onClose = onClose
        self.onStash = onStash
    }

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

            if let onStash {
                Menu("More actions", systemImage: "ellipsis") {
                    Button("Stash changes", action: onStash)
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                .contentShape(Rectangle())
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("More actions")
                .accessibilityLabel("More actions")
            }

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
        onClose: {},
        onStash: {}
    )
    .frame(width: WorkbenchMetrics.sidePanelWidth)
    .padding()
}
