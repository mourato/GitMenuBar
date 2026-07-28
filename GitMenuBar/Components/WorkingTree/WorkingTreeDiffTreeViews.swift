import SwiftUI

struct WorkingTreeDiffTreeView: View {
    let files: [WorkingTreeRowAdapter]
    let actionIcon: String
    let selectedItemID: MainMenuSelectableItem?
    let onSelect: (MainMenuSelectableItem) -> Void
    let onStageToggle: (String) -> Void
    let onOpen: (String) -> Void
    let onDiscard: (String, WorkingTreeFileStatus) -> Void
    let onReveal: (String) -> Void
    @Binding var allDirectoriesExpanded: Bool
    @Binding var directoryExpansionOverrides: [String: Bool]

    private var treeNodes: [DiffTreeNode] {
        DiffTreeBuilder.buildDiffTree(files.map(\.file.diffTreeFileInput))
    }

    private var hasDirectoryNodes: Bool {
        files.contains { !$0.file.directoryPath.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            ForEach(treeNodes, id: \.self) { node in
                WorkingTreeDiffTreeNodeView(
                    node: node,
                    depth: 0,
                    hasDirectoryNodes: hasDirectoryNodes,
                    allDirectoriesExpanded: allDirectoriesExpanded,
                    directoryExpansionOverrides: directoryExpansionOverrides,
                    actionIcon: actionIcon,
                    selectedItemID: selectedItemID,
                    adapterForPath: adapter(for:),
                    onToggleDirectory: toggleDirectory,
                    onSelect: onSelect,
                    onStageToggle: onStageToggle,
                    onOpen: onOpen,
                    onDiscard: onDiscard,
                    onReveal: onReveal
                )
            }
        }
    }

    private func adapter(for path: String) -> WorkingTreeRowAdapter? {
        files.first { $0.file.path == path }
    }

    private func toggleDirectory(_ path: String) {
        let isExpanded = directoryExpansionOverrides[path] ?? allDirectoriesExpanded
        directoryExpansionOverrides[path] = !isExpanded
    }
}

struct WorkingTreeDiffTreeNodeView: View {
    let node: DiffTreeNode
    let depth: Int
    let hasDirectoryNodes: Bool
    let allDirectoriesExpanded: Bool
    let directoryExpansionOverrides: [String: Bool]
    let actionIcon: String
    let selectedItemID: MainMenuSelectableItem?
    let adapterForPath: (String) -> WorkingTreeRowAdapter?
    let onToggleDirectory: (String) -> Void
    let onSelect: (MainMenuSelectableItem) -> Void
    let onStageToggle: (String) -> Void
    let onOpen: (String) -> Void
    let onDiscard: (String, WorkingTreeFileStatus) -> Void
    let onReveal: (String) -> Void

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
            .frame(minHeight: WorkingTreeLayoutMetrics.rowHeight)
            .contentShape(Rectangle())
            .accessibilityLabel("\(name) folder")
            .accessibilityHint(isExpanded ? "Collapse folder." : "Expand folder.")
            .accessibilityValue(folderAccessibilityValue(for: stat))

            if isExpanded {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    ForEach(children, id: \.self) { child in
                        WorkingTreeDiffTreeNodeView(
                            node: child,
                            depth: depth + 1,
                            hasDirectoryNodes: hasDirectoryNodes,
                            allDirectoriesExpanded: allDirectoriesExpanded,
                            directoryExpansionOverrides: directoryExpansionOverrides,
                            actionIcon: actionIcon,
                            selectedItemID: selectedItemID,
                            adapterForPath: adapterForPath,
                            onToggleDirectory: onToggleDirectory,
                            onSelect: onSelect,
                            onStageToggle: onStageToggle,
                            onOpen: onOpen,
                            onDiscard: onDiscard,
                            onReveal: onReveal
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

    @ViewBuilder
    private func fileRow(name: String, path: String, stat: DiffTreeStat?) -> some View {
        if let adapter = adapterForPath(path) {
            WorkingTreeDiffTreeFileRowView(
                name: name,
                path: path,
                depth: depth,
                showsChevronSpacer: hasDirectoryNodes || depth > 0,
                stat: stat,
                file: adapter.file,
                actionIcon: actionIcon,
                actionHelp: adapter.actions.primaryLabel,
                isSelected: selectedItemID == adapter.id,
                onSelect: { onSelect(adapter.id) },
                onAction: { onStageToggle(path) },
                onOpen: { onOpen(path) },
                onDiscard: adapter.actions.canDiscard
                    ? {
                        onSelect(adapter.id)
                        onDiscard(path, adapter.file.status)
                    } : nil,
                onReveal: { onReveal(path) }
            )
        }
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
    var isSelected = false
    var onSelect: (() -> Void)?
    let onAction: () -> Void
    var onOpen: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onReveal: (() -> Void)?

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: WorkbenchMetrics.chipSpacing) {
            rowContent

            Text(file.status.symbol)
                .font(WorkbenchTypography.body.weight(.semibold))
                .foregroundColor(Color(nsColor: file.status.foregroundColor))
                .frame(width: WorkingTreeLayoutMetrics.statusColumnWidth, alignment: .trailing)
        }
        .padding(.vertical, WorkingTreeLayoutMetrics.rowVerticalPadding)
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
        .frame(minHeight: WorkingTreeLayoutMetrics.rowHeight)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
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
        .onHover { inside in
            isHovered = inside
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Press Return to open, or Delete to discard when available.")
        .contextMenu {
            Button("Open File") {
                onOpen?()
            }
            if let onDiscard {
                Button("Discard Changes") {
                    onDiscard()
                }
            }
            Button(actionHelp) {
                onAction()
            }
            Divider()
            Button("Reveal in Finder") {
                onReveal?()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onAction) {
                Label(actionHelp, systemImage: actionIcon)
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if let onDiscard {
                Button(role: .destructive, action: onDiscard) {
                    Label("Discard", systemImage: "arrow.uturn.backward")
                }
            }
        }
        .pressable()
    }

    private var rowContent: some View {
        HStack(spacing: WorkbenchMetrics.chipSpacing) {
            if showsChevronSpacer {
                Color.clear
                    .frame(width: 12, height: 12)
            }

            FileTypeIconView(path: path)

            Text(name)
                .font(WorkbenchTypography.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .strikethrough(file.status.isDeleted, color: .secondary)

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

            ZStack(alignment: .trailing) {
                if let stat {
                    WorkingTreeLineDiffView(
                        addedCount: stat.additions,
                        removedCount: stat.deletions
                    )
                    .opacity(isHovered ? 0 : 1)
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
                        accessibilityLabel: "\(actionHelp) for \(name)",
                        action: onAction
                    )
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .layoutPriority(2)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        value += ", status \(file.status.symbol)"
        return value
    }

    private var backgroundColor: Color {
        if isSelected {
            return WorkbenchPalette.selectedFill()
        }

        if isHovered {
            return WorkbenchPalette.hoverFill()
        }

        return Color.clear
    }
}
