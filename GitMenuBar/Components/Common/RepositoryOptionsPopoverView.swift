import SwiftUI

struct RepositoryOptionsPopoverView: View {
    let visibilityStatusDescription: String
    let visibilityActionTitle: String
    let onToggleVisibility: () -> Void
    let onDeleteRepository: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repository Options")
                    .font(WorkbenchTypography.sectionLabel)

                Text(visibilityStatusDescription)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button(action: onToggleVisibility) {
                actionRow(
                    title: visibilityActionTitle,
                    icon: .lock
                )
            }
            .workbenchRow()

            Button(role: .destructive, action: onDeleteRepository) {
                actionRow(
                    title: "Delete Repository",
                    icon: .trash2
                )
            }
            .workbenchDestructiveRow()
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(width: 280, alignment: .leading)
        .workbenchPanelSurface(material: .thin)
    }

    private func actionRow(title: String, icon: LucideIconName) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            LucideIconView(name: icon, size: 14)
                .foregroundStyle(.secondary)

            Text(title)
                .font(WorkbenchTypography.body)

            Spacer()
        }
    }
}

#Preview("Repository Options Popover") {
    RepositoryOptionsPopoverView(
        visibilityStatusDescription: "This repository is currently private.",
        visibilityActionTitle: "Make Public",
        onToggleVisibility: {},
        onDeleteRepository: {}
    )
}
