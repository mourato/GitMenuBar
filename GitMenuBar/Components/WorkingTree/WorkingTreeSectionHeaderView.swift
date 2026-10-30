import SwiftUI

struct WorkingTreeSectionHeaderView: View {
    let title: String
    let summary: WorkingTreeSectionSummary
    @Binding var isCollapsed: Bool
    let actionIcon: String
    let actionHelp: String
    let showsAction: Bool
    let onAction: () -> Void
    var onDiscardAll: (() -> Void)?
    var showsDirectoryControls = false
    var allDirectoriesExpanded = true
    var onToggleAllDirectories: (() -> Void)?
    var displayMode: Binding<AppPreferences.WorkingTreeDisplayMode>?

    @State private var isHovered = false
    @FocusState private var isHeaderFocused: Bool
    @FocusState private var isActionFocused: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActionsVisible: Bool {
        isHovered || isHeaderFocused || isActionFocused
    }

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            headerToggle

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

            trailingContent
        }
        .padding(.vertical, WorkbenchMetrics.headerVerticalPadding)
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
        .background(
            RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius)
                .fill(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
                .stroke(
                    WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast)
                        .opacity(colorSchemeContrast == .increased ? 1 : 0),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
            value: isHovered
        )
        .onHover { inside in
            isHovered = inside
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isCollapsed ? "Expand \(title) section" : "Collapse \(title) section") {
            toggleSection()
        }
        .accessibilityAction(named: actionHelp) {
            if showsAction {
                onAction()
            }
        }
    }

    private var headerToggle: some View {
        Button(action: toggleSection) {
            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .accessibilityHidden(true)
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))

                Text(title)
                    .font(WorkbenchTypography.captionStrong)
                    .textCase(.uppercase)
                    .tracking(WorkbenchTypography.tracking(for: WorkbenchTypography.caption))
                    .foregroundStyle(.secondary)

                Text("\(summary.fileCount)")
                    .font(WorkbenchTypography.captionStrong)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(
                        WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                        value: summary.fileCount
                    )
            }
            .lineLimit(1)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .focused($isHeaderFocused)
        .accessibilityLabel("\(title) section, \(summary.fileCount) files")
        .accessibilityHint(isCollapsed ? "Expands the section." : "Collapses the section.")
    }

    private var trailingContent: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            if summary.addedLineCount > 0 || summary.removedLineCount > 0 {
                WorkingTreeLineDiffView(
                    addedCount: summary.addedLineCount,
                    removedCount: summary.removedLineCount
                )
            }

            actionsGroup

            if let displayMode {
                viewModeToggle(displayMode: displayMode)
            }
        }
    }

    @ViewBuilder
    private var actionsGroup: some View {
        if showsAction {
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                if let onDiscardAll {
                    Button(action: onDiscardAll) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(WorkbenchTypography.captionStrong)
                            .foregroundStyle(.primary)
                            .frame(
                                width: WorkingTreeLayoutMetrics.actionHitTarget,
                                height: WorkingTreeLayoutMetrics.actionHitTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .workbenchIcon()
                    .help("Discard all unstaged changes")
                    .accessibilityLabel("Discard all unstaged changes")
                    .focused($isActionFocused)

                    Spacer().frame(width: WorkbenchMetrics.compactSpacing)
                }

                if showsDirectoryControls, let onToggleAllDirectories {
                    Button(action: onToggleAllDirectories) {
                        Image(
                            systemName: allDirectoriesExpanded
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right"
                        )
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundStyle(.primary)
                        .frame(
                            width: WorkingTreeLayoutMetrics.actionHitTarget,
                            height: WorkingTreeLayoutMetrics.actionHitTarget
                        )
                        .contentShape(Rectangle())
                    }
                    .workbenchIcon()
                    .help(allDirectoriesExpanded ? "Collapse all folders in \(title.lowercased()) changes" : "Expand all folders in \(title.lowercased()) changes")
                    .accessibilityLabel(allDirectoriesExpanded ? "Collapse all folders in \(title.lowercased()) changes" : "Expand all folders in \(title.lowercased()) changes")
                    .focused($isActionFocused)
                }

                Button(action: onAction) {
                    Image(systemName: actionIcon)
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundStyle(.primary)
                        .frame(
                            width: WorkingTreeLayoutMetrics.actionHitTarget,
                            height: WorkingTreeLayoutMetrics.actionHitTarget
                        )
                        .contentShape(Rectangle())
                }
                .workbenchIcon()
                .help(actionHelp)
                .accessibilityLabel(actionHelp)
                .focused($isActionFocused)
            }
            .opacity(isActionsVisible ? 1 : 0)
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
                value: isActionsVisible
            )
        }
    }

    private func viewModeToggle(displayMode: Binding<AppPreferences.WorkingTreeDisplayMode>) -> some View {
        Picker("View mode", selection: displayMode) {
            Image(systemName: "list.bullet.indent")
                .tag(AppPreferences.WorkingTreeDisplayMode.tree)
                .accessibilityLabel("Tree view")
                .help("Tree view")

            Image(systemName: "list.bullet")
                .tag(AppPreferences.WorkingTreeDisplayMode.flat)
                .accessibilityLabel("Flat view")
                .help("Flat view")
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .accessibilityLabel("Working tree view mode")
        .help(displayMode.wrappedValue == .tree ? "Tree view" : "Flat view")
    }

    private func toggleSection() {
        withAnimation(
            WorkbenchMotion.adaptive(WorkbenchMotion.settle, usesReducedMotion: reduceMotion)
        ) {
            isCollapsed.toggle()
        }
    }
}

private struct WorkingTreeSectionHeaderPreviewContainer: View {
    @State private var isCollapsed = false
    @State private var allDirectoriesExpanded = true
    @State private var directoryExpansionOverrides: [String: Bool] = [:]

    private let previewFiles: [WorkingTreeRowAdapter] = [
        .staged(file: WorkingTreeFile(
            path: "GitMenuBar/Pages/MainMenu/MainMenuContent.swift",
            lineDiff: LineDiffStats(added: 23, removed: 8),
            status: .modified
        )),
        .staged(file: WorkingTreeFile(
            path: "GitMenuBar/Services/Git/GitManager.swift",
            lineDiff: LineDiffStats(added: 19, removed: 4),
            status: .modified
        )),
        .staged(file: WorkingTreeFile(
            path: "GitMenuBar/Resources/PreviewSeed.json",
            lineDiff: LineDiffStats(added: 0, removed: 0),
            status: .untracked
        ))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkingTreeSectionHeaderView(
                title: "Staged",
                summary: previewFiles.map(\.file).sectionSummary,
                isCollapsed: $isCollapsed,
                actionIcon: "minus.circle",
                actionHelp: "Unstage all staged changes",
                showsAction: true,
                onAction: {},
                onDiscardAll: nil,
                showsDirectoryControls: !isCollapsed,
                allDirectoriesExpanded: allDirectoriesExpanded,
                onToggleAllDirectories: {
                    allDirectoriesExpanded.toggle()
                    directoryExpansionOverrides = [:]
                }
            )

            if !isCollapsed {
                WorkingTreeDiffTreeView(
                    files: previewFiles,
                    actionIcon: "minus.circle",
                    selectedItemID: nil,
                    onSelect: { _ in },
                    onStageToggle: { _ in },
                    onOpen: { _ in },
                    onDiscard: { _, _ in },
                    onReveal: { _ in },
                    allDirectoriesExpanded: $allDirectoriesExpanded,
                    directoryExpansionOverrides: $directoryExpansionOverrides
                )
            }
        }
        .padding()
        .frame(width: 380, alignment: .leading)
    }
}

#Preview("Working Tree Section Header") {
    WorkingTreeSectionHeaderPreviewContainer()
}

#Preview("Unstaged Section Header with Toggle") {
    struct UnstagedPreview: View {
        @State private var isCollapsed = false
        @State private var displayMode = AppPreferences.WorkingTreeDisplayMode.tree

        var body: some View {
            WorkingTreeSectionHeaderView(
                title: "Unstaged",
                summary: WorkingTreeSectionSummary(
                    fileCount: 3,
                    addedLineCount: 42,
                    removedLineCount: 11
                ),
                isCollapsed: $isCollapsed,
                actionIcon: "plus.circle",
                actionHelp: "Stage all unstaged changes",
                showsAction: true,
                onAction: {},
                onDiscardAll: {},
                displayMode: $displayMode
            )
            .padding()
            .frame(width: 380, alignment: .leading)
        }
    }

    return UnstagedPreview()
}
