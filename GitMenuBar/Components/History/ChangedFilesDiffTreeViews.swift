import SwiftUI

struct ChangedFilesDiffTreeNodeView: View {
    let node: DiffTreeNode
    let depth: Int
    let hasDirectoryNodes: Bool
    let allDirectoriesExpanded: Bool
    let directoryExpansionOverrides: [String: Bool]
    let onToggleDirectory: (String) -> Void
    let onOpenFile: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch node {
        case let .directory(name, path, stat, children):
            directoryRow(name: name, path: path, stat: stat, children: children)
        case let .file(name, path, stat):
            fileRow(name: name, path: path, stat: stat)
        }
    }

    @ViewBuilder
    private func directoryRow(
        name: String,
        path: String,
        stat: DiffTreeStat,
        children: [DiffTreeNode]
    ) -> some View {
        let isExpanded = directoryExpansionOverrides[path] ?? allDirectoriesExpanded

        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Button {
                onToggleDirectory(path)
            } label: {
                ChangedFilesTreeRowChrome(
                    depth: depth,
                    showsChevronSpacer: hasDirectoryNodes || depth > 0,
                    leadingIcon: .directory(isExpanded: isExpanded),
                    title: name,
                    stat: stat,
                    showsChevron: true,
                    isExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name) folder")
            .accessibilityHint(isExpanded ? "Collapse folder." : "Expand folder.")
            .accessibilityValue(folderAccessibilityValue(for: stat))

            if isExpanded {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    ForEach(children, id: \.self) { child in
                        ChangedFilesDiffTreeNodeView(
                            node: child,
                            depth: depth + 1,
                            hasDirectoryNodes: hasDirectoryNodes,
                            allDirectoriesExpanded: allDirectoriesExpanded,
                            directoryExpansionOverrides: directoryExpansionOverrides,
                            onToggleDirectory: onToggleDirectory,
                            onOpenFile: onOpenFile
                        )
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
            value: isExpanded
        )
    }

    private func fileRow(name: String, path: String, stat: DiffTreeStat?) -> some View {
        Button {
            onOpenFile(path)
        } label: {
            ChangedFilesTreeRowChrome(
                depth: depth,
                showsChevronSpacer: hasDirectoryNodes || depth > 0,
                leadingIcon: .file(path: path),
                title: name,
                stat: stat,
                showsChevron: false,
                isExpanded: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fileAccessibilityLabel(name: name, stat: stat))
        .accessibilityHint("Opens this file.")
    }

    private func folderAccessibilityValue(for stat: DiffTreeStat) -> String {
        var value = ""
        if stat.additions > 0 {
            value += "\(stat.additions) additions"
        }
        if stat.deletions > 0 {
            if !value.isEmpty {
                value += ", "
            }
            value += "\(stat.deletions) deletions"
        }
        return value.isEmpty ? "No line changes" : value
    }

    private func fileAccessibilityLabel(name: String, stat: DiffTreeStat?) -> String {
        var label = name
        guard let stat else {
            return label
        }
        if stat.additions > 0 {
            label += ", \(stat.additions) additions"
        }
        if stat.deletions > 0 {
            label += ", \(stat.deletions) deletions"
        }
        return label
    }
}

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
                .font(WorkbenchTypography.captionStrong.monospaced())
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
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
        .padding(.leading, CGFloat(depth) * 14)
        .background(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct ChangedFilesPreviewFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                totalWidth = max(totalWidth, currentX - spacing)
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            if currentX > 0 {
                currentX += spacing
            }

            currentX += size.width
            rowHeight = max(rowHeight, size.height)
            totalHeight = currentY + rowHeight
            totalWidth = max(totalWidth, currentX)
        }

        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
