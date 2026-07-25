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
                    symbol: "lock.circle"
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDeleteRepository) {
                actionRow(
                    title: "Delete Repository…",
                    symbol: "trash"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(width: 280, alignment: .leading)
    }

    private func actionRow(title: String, symbol: String) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: symbol)
                .font(WorkbenchTypography.detail)
                .foregroundStyle(.secondary)

            Text(title)
                .font(WorkbenchTypography.body)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                .fill(WorkbenchPalette.hoverFill())
        )
        .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
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
