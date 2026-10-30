import SwiftUI

enum WorkingTreeLayoutMetrics {
    static let rowHeight: CGFloat = 32
    static let rowVerticalPadding: CGFloat = WorkbenchMetrics.headerVerticalPadding
    /// Minimum interactive target for row/header icon actions.
    static let actionHitTarget: CGFloat = WorkbenchMetrics.iconHitTarget
    static let diffColumnWidth: CGFloat = 72
    static let statusColumnWidth: CGFloat = 14
    static let trailingContentPadding: CGFloat = 12
}

struct WorkingTreeLineDiffView: View {
    let addedCount: Int
    let removedCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if addedCount > 0 {
                Text("+\(addedCount)")
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.green)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(
                        WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                        value: addedCount
                    )
            }
            if removedCount > 0 {
                Text("−\(removedCount)")
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.red)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(
                        WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                        value: removedCount
                    )
            }
        }
        .font(WorkbenchTypography.captionStrong)
        .fixedSize(horizontal: true, vertical: false)
    }
}

@MainActor
func workingTreeRowIconButton(
    systemName: String,
    help: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(WorkbenchTypography.captionStrong)
            .foregroundStyle(.primary)
            .frame(
                width: WorkingTreeLayoutMetrics.actionHitTarget,
                height: WorkingTreeLayoutMetrics.actionHitTarget
            )
            .contentShape(Rectangle())
    }
    .workbenchIcon()
    .help(help)
    .accessibilityLabel(accessibilityLabel)
}

#Preview("Working Tree Line Diff") {
    WorkingTreeLineDiffView(addedCount: 23, removedCount: 8)
        .padding()
}

struct WorkingTreeDiffTreeFileRowView: View {
    let name: String
    let path: String
    let depth: Int
    let showsChevronSpacer: Bool
    let stat: DiffTreeStat?
    let file: WorkingTreeFile
    let actionIcon: String
    let actionHelp: String
    let actionAccessibilityLabel: String
    var isSelected = false
    var onSelect: (() -> Void)?
    let onAction: () -> Void
    var onOpen: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onReveal: (() -> Void)?
    var isFlatMode: Bool = false

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: WorkbenchMetrics.chipSpacing) {
            rowContent

            statusBadge
        }
        .padding(.vertical, WorkingTreeLayoutMetrics.treeRowVerticalPadding)
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
        .frame(minHeight: WorkingTreeLayoutMetrics.treeRowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
            value: isHovered
        )
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
            value: isSelected
        )
        .onTapGesture {
            onSelect?()
        }
        .onTapGesture(count: 2) {
            onOpen?()
        }
        .onKeyPress(.space) {
            guard isSelected else { return .ignored }
            onAction()
            return .handled
        }
        .onHover { inside in
            isHovered = inside
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Press Return to open, or Delete to discard when available.")
        .accessibilityAction(named: Text("Open \(name)")) {
            onOpen?()
        }
        .accessibilityAction(named: Text(actionAccessibilityLabel)) {
            onAction()
        }
        .workingTreeRowDiscardAccessibilityAction(fileName: name, action: onDiscard)
        .accessibilityAction(named: Text("Reveal \(name) in Finder")) {
            onReveal?()
        }
        .contextMenu {
            Button("Open \(name)") { onOpen?() }
            if let onDiscard {
                Button("Discard changes in \(name)") { onDiscard() }
            }
            Button(actionAccessibilityLabel) { onAction() }
            Divider()
            Button("Reveal \(name) in Finder") { onReveal?() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onAction) {
                Label(actionAccessibilityLabel, systemImage: actionIcon)
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onDiscard {
                Button(role: .destructive, action: onDiscard) {
                    Label("Discard changes in \(name)", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            if !isFlatMode, depth > 0 {
                WorkingTreeIndentGuidesView(depth: depth)
            }

            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                if showsChevronSpacer {
                    Color.clear
                        .frame(width: WorkingTreeLayoutMetrics.treeChevronWidth, height: WorkingTreeLayoutMetrics.treeChevronWidth)
                }

                Image(systemName: "doc")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .center)
                    .accessibilityHidden(true)

                HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.microSpacing) {
                    Text(name)
                        .font(WorkbenchTypography.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .strikethrough(file.status.isDeleted, color: .secondary)
                        .layoutPriority(1)

                    if isFlatMode, !file.directoryPath.isEmpty {
                        Text(flatDirectoryName)
                            .font(WorkbenchTypography.detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .layoutPriority(0)
                            .help(path)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: WorkbenchMetrics.compactSpacing)

                ZStack(alignment: .trailing) {
                    if let stat {
                        WorkingTreeLineDiffView(
                            addedCount: stat.additions,
                            removedCount: stat.deletions
                        )
                        .opacity(showsActions ? 0 : 1)
                    }

                    HStack(spacing: 0) {
                        if let onOpen {
                            workingTreeRowIconButton(
                                systemName: "doc",
                                help: "Open File",
                                accessibilityLabel: "Open \(name)",
                                action: onOpen
                            )
                        }

                        if let onDiscard {
                            workingTreeRowIconButton(
                                systemName: "arrow.uturn.backward",
                                help: "Discard Changes",
                                accessibilityLabel: "Discard changes in \(name)",
                                action: onDiscard
                            )
                        }

                        workingTreeRowIconButton(
                            systemName: actionIcon,
                            help: actionHelp,
                            accessibilityLabel: actionAccessibilityLabel,
                            action: onAction
                        )
                    }
                    .opacity(showsActions ? 1 : 0)
                    .allowsHitTesting(showsActions)
                }
                .layoutPriority(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(path)
    }

    private var accessibilityLabel: String {
        var value = name
        if let stat {
            if stat.additions > 0 {
                value += ", \(stat.additions) additions"
            }
            if stat.deletions > 0 {
                value += ", \(stat.deletions) deletions"
            }
        }
        return value + ", status \(file.status.symbol)"
    }

    private var showsActions: Bool {
        isHovered || isSelected
    }

    private var flatDirectoryName: String {
        (file.directoryPath as NSString).lastPathComponent
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch file.status {
        case .modified:
            EmptyView()
        case .deleted, .untracked:
            Circle()
                .fill(Color(nsColor: file.status.foregroundColor))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(WorkingTreeLayoutMetrics.treeSelectionOpacity))
        } else if isHovered {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                .fill(.quaternary)
        }
    }
}

private extension View {
    @ViewBuilder
    func workingTreeRowDiscardAccessibilityAction(
        fileName: String,
        action: (() -> Void)?
    ) -> some View {
        if let action {
            accessibilityAction(named: Text("Discard changes in \(fileName)")) {
                action()
            }
        } else {
            self
        }
    }
}
