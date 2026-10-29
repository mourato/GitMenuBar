import SwiftUI

struct ChangedFilesTreeRowChrome: View {
    let depth: Int
    let showsChevronSpacer: Bool
    let leadingIcon: DiffTreeLeadingIcon
    let title: String
    let stat: DiffTreeStat?
    let showsChevron: Bool
    let isExpanded: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: WorkbenchMetrics.chipSpacing) {
            if showsChevron {
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12, alignment: .center)
            } else if showsChevronSpacer {
                Color.clear
                    .frame(width: 12, height: 12)
            }

            DiffTreeLeadingIconView(icon: leadingIcon)

            Text(title)
                .font(WorkbenchTypography.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

            if let stat {
                WorkingTreeLineDiffView(
                    addedCount: stat.additions,
                    removedCount: stat.deletions
                )
            }
        }
        .padding(.vertical, WorkingTreeLayoutMetrics.rowVerticalPadding)
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
        .padding(.leading, CGFloat(depth) * 14)
        .frame(minHeight: WorkingTreeLayoutMetrics.rowHeight)
        .background(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

#Preview("Changed Files Tree Row") {
    ChangedFilesTreeRowChrome(
        depth: 1,
        showsChevronSpacer: true,
        leadingIcon: .file(path: "CommitDetailPageView.swift"),
        title: "CommitDetailPageView.swift",
        stat: DiffTreeStat(additions: 12, deletions: 3),
        showsChevron: false,
        isExpanded: false
    )
    .padding()
    .frame(width: 360)
}
