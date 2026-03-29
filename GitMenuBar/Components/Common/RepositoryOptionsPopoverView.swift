import SwiftUI

struct RepositoryOptionsPopoverView: View {
    let visibilityStatusDescription: String
    let visibilityActionTitle: String
    let onToggleVisibility: () -> Void
    let onDeleteRepository: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MacChromeMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repository Options")
                    .font(MacChromeTypography.sectionLabel)

                Text(visibilityStatusDescription)
                    .font(MacChromeTypography.caption)
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
        .padding(MacChromeMetrics.panelPadding)
        .frame(width: 280, alignment: .leading)
    }

    private func actionRow(title: String, symbol: String) -> some View {
        HStack(spacing: MacChromeMetrics.compactSpacing) {
            Image(systemName: symbol)
                .font(MacChromeTypography.detail)
                .foregroundStyle(.secondary)

            Text(title)
                .font(MacChromeTypography.body)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous)
                .fill(MacChromePalette.hoverFill())
        )
        .contentShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
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
