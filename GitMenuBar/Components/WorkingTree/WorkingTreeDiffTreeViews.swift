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
    let matchedGeometryNamespace: Namespace.ID?
    let matchedGeometryPaths: Set<String>
    let matchedGeometrySectionID: String

    private let treeNodes: [DiffTreeNode]
    private let hasDirectoryNodes: Bool
    private let adaptersByPath: [String: WorkingTreeRowAdapter]

    init(
        files: [WorkingTreeRowAdapter],
        actionIcon: String,
        selectedItemID: MainMenuSelectableItem?,
        onSelect: @escaping (MainMenuSelectableItem) -> Void,
        onStageToggle: @escaping (String) -> Void,
        onOpen: @escaping (String) -> Void,
        onDiscard: @escaping (String, WorkingTreeFileStatus) -> Void,
        onReveal: @escaping (String) -> Void,
        allDirectoriesExpanded: Binding<Bool>,
        directoryExpansionOverrides: Binding<[String: Bool]>,
        matchedGeometryNamespace: Namespace.ID? = nil,
        matchedGeometryPaths: Set<String> = [],
        matchedGeometrySectionID: String = ""
    ) {
        self.files = files
        self.actionIcon = actionIcon
        self.selectedItemID = selectedItemID
        self.onSelect = onSelect
        self.onStageToggle = onStageToggle
        self.onOpen = onOpen
        self.onDiscard = onDiscard
        self.onReveal = onReveal
        _allDirectoriesExpanded = allDirectoriesExpanded
        _directoryExpansionOverrides = directoryExpansionOverrides
        self.matchedGeometryNamespace = matchedGeometryNamespace
        self.matchedGeometryPaths = matchedGeometryPaths
        self.matchedGeometrySectionID = matchedGeometrySectionID

        treeNodes = DiffTreeBuilder.buildDiffTree(files.map(\.file.diffTreeFileInput))
        hasDirectoryNodes = files.contains { !$0.file.directoryPath.isEmpty }
        adaptersByPath = Dictionary(files.map { ($0.file.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let context = WorkingTreeDiffTreeContext(
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
            onReveal: onReveal,
            matchedGeometryNamespace: matchedGeometryNamespace,
            matchedGeometryPaths: matchedGeometryPaths,
            matchedGeometrySectionID: matchedGeometrySectionID
        )

        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            ForEach(treeNodes, id: \.workingTreeVisualID) { node in
                WorkingTreeDiffTreeNodeView(
                    node: node,
                    depth: 0,
                    context: context
                )
            }
        }
    }

    private func adapter(for path: String) -> WorkingTreeRowAdapter? {
        adaptersByPath[path]
    }

    private func toggleDirectory(_ path: String) {
        let isExpanded = directoryExpansionOverrides[path] ?? allDirectoriesExpanded
        directoryExpansionOverrides[path] = !isExpanded
    }
}

private extension DiffTreeNode {
    var workingTreeVisualID: String {
        switch self {
        case let .directory(_, path, _, _): "directory:\(path)"
        case let .file(_, path, _): "file:\(path)"
        }
    }
}

private struct WorkingTreeDiffTreeContext {
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
    let matchedGeometryNamespace: Namespace.ID?
    let matchedGeometryPaths: Set<String>
    let matchedGeometrySectionID: String

    func matchedGeometryID(for path: String, usesReducedMotion: Bool) -> String {
        guard !usesReducedMotion, matchedGeometryPaths.contains(path) else {
            return "\(matchedGeometrySectionID):\(path)"
        }
        return path
    }
}

extension WorkingTreeLayoutMetrics {
    static let treeDepthIndentation: CGFloat = 14
    static let treeRowHeight: CGFloat = 24
    static let treeRowVerticalPadding: CGFloat = WorkbenchMetrics.headerVerticalPadding
    static let treeChevronWidth: CGFloat = 12
    static let treeChevronFontSize: CGFloat = 9
    static let treeIndentGuideWidth: CGFloat = 1
    static let treeIndentGuideOpacity: Double = 0.07
    static let treeSelectionOpacity: Double = 0.12
}

struct WorkingTreeIndentGuidesView: View {
    let depth: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< depth, id: \.self) { _ in
                ZStack(alignment: .leading) {
                    Color.clear
                    Rectangle()
                        .fill(Color.primary.opacity(WorkingTreeLayoutMetrics.treeIndentGuideOpacity))
                        .frame(width: WorkingTreeLayoutMetrics.treeIndentGuideWidth)
                        .offset(x: (WorkingTreeLayoutMetrics.treeChevronWidth - WorkingTreeLayoutMetrics.treeIndentGuideWidth) / 2)
                }
                .frame(width: WorkingTreeLayoutMetrics.treeDepthIndentation)
                .frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

struct WorkingTreeDiffTreeDirectoryRowView: View {
    let name: String
    let depth: Int
    let isExpanded: Bool
    let stat: DiffTreeStat?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            if depth > 0 {
                WorkingTreeIndentGuidesView(depth: depth)
            }

            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .font(.system(size: WorkingTreeLayoutMetrics.treeChevronFontSize, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: WorkingTreeLayoutMetrics.treeChevronWidth, alignment: .center)

                FileTypeDirectoryIconView(isExpanded: isExpanded)

                titleView

                Spacer(minLength: WorkbenchMetrics.compactSpacing)

                if let stat {
                    WorkingTreeLineDiffView(
                        addedCount: stat.additions,
                        removedCount: stat.deletions
                    )
                }
            }
        }
        .padding(.vertical, WorkingTreeLayoutMetrics.treeRowVerticalPadding)
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
        .frame(minHeight: WorkingTreeLayoutMetrics.treeRowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isHovered {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                .fill(.quaternary)
        }
    }

    private var titleView: some View {
        Group {
            if let lastSlashIndex = name.lastIndex(of: "/") {
                let prefix = String(name[...lastSlashIndex])
                let leaf = String(name[name.index(after: lastSlashIndex)...])
                Text(prefix).foregroundStyle(.secondary) + Text(leaf).foregroundStyle(.primary).bold()
            } else {
                Text(name).foregroundStyle(.primary)
            }
        }
        .font(WorkbenchTypography.body)
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

struct WorkingTreeDiffTreeNodeView: View {
    let node: DiffTreeNode
    let depth: Int
    fileprivate let context: WorkingTreeDiffTreeContext

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
        let isExpanded = context.directoryExpansionOverrides[path] ?? context.allDirectoriesExpanded

        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Button {
                context.onToggleDirectory(path)
            } label: {
                WorkingTreeDiffTreeDirectoryRowView(
                    name: name,
                    depth: depth,
                    isExpanded: isExpanded,
                    stat: nil
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("\(name) folder")
            .accessibilityHint(isExpanded ? "Collapse folder." : "Expand folder.")
            .accessibilityValue(folderAccessibilityValue(for: stat))

            if isExpanded {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    ForEach(children, id: \.workingTreeVisualID) { child in
                        childNodeView(for: child)
                    }
                }
                .transition(WorkbenchMotion.workingTreeSectionTransition(usesReducedMotion: reduceMotion))
            }
        }
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.press, usesReducedMotion: reduceMotion),
            value: isExpanded
        )
    }

    private func childNodeView(for child: DiffTreeNode) -> WorkingTreeDiffTreeNodeView {
        WorkingTreeDiffTreeNodeView(
            node: child,
            depth: depth + 1,
            context: context
        )
    }

    @ViewBuilder
    private func fileRow(name: String, path: String, stat: DiffTreeStat?) -> some View {
        if let adapter = context.adapterForPath(path) {
            let row = WorkingTreeDiffTreeFileRowView(
                name: name,
                path: path,
                depth: depth,
                showsChevronSpacer: context.hasDirectoryNodes || depth > 0,
                stat: stat,
                file: adapter.file,
                actionIcon: context.actionIcon,
                actionHelp: adapter.actions.primaryLabel,
                actionAccessibilityLabel: adapter.actions.accessibilityLabel,
                isSelected: context.selectedItemID == adapter.id,
                onSelect: { context.onSelect(adapter.id) },
                onAction: { context.onStageToggle(path) },
                onOpen: { context.onOpen(path) },
                onDiscard: adapter.actions.canDiscard
                    ? {
                        context.onSelect(adapter.id)
                        context.onDiscard(path, adapter.file.status)
                    } : nil,
                onReveal: { context.onReveal(path) }
            )
            if let namespace = context.matchedGeometryNamespace {
                row
                    .matchedGeometryEffect(
                        id: context.matchedGeometryID(for: path, usesReducedMotion: reduceMotion),
                        in: namespace,
                        properties: reduceMotion ? [] : .frame
                    )
                    .transition(WorkbenchMotion.workingTreeSectionTransition(usesReducedMotion: reduceMotion))
            } else {
                row
                    .transition(WorkbenchMotion.workingTreeSectionTransition(usesReducedMotion: reduceMotion))
            }
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
