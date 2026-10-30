import SwiftUI

struct WorkingTreeSectionView: View {
    let title: String
    let summary: WorkingTreeSectionSummary
    let files: [WorkingTreeRowAdapter]
    @Binding var isCollapsed: Bool
    @Binding var displayMode: AppPreferences.WorkingTreeDisplayMode
    let matchedGeometryNamespace: Namespace.ID?
    let matchedGeometryPaths: Set<String>
    let matchedGeometrySectionID: String
    let selectedItemID: MainMenuSelectableItem?
    let onSelect: (MainMenuSelectableItem) -> Void
    let onStageToggle: (String) -> Void
    let onOpen: (String) -> Void
    let onDiscard: (String, WorkingTreeFileStatus) -> Void
    let onReveal: (String) -> Void
    let onAction: () -> Void
    let onDiscardAll: (() -> Void)?
    let actionIcon: String
    let actionHelp: String
    var showsViewModeToggle = false
    var showsEmptyState = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var allDirectoriesExpanded = true
    @State private var directoryExpansionOverrides: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkingTreeSectionHeaderView(
                title: title,
                summary: summary,
                isCollapsed: $isCollapsed,
                actionIcon: actionIcon,
                actionHelp: actionHelp,
                showsAction: !files.isEmpty,
                onAction: onAction,
                onDiscardAll: onDiscardAll,
                showsDirectoryControls: showsDirectoryControls,
                allDirectoriesExpanded: allDirectoriesExpanded,
                onToggleAllDirectories: toggleAllDirectories,
                displayMode: showsViewModeToggle ? $displayMode : nil
            )

            if !isCollapsed {
                if files.isEmpty {
                    if showsEmptyState {
                        stagedEmptyStateView
                    }
                } else if displayMode == .flat {
                    flatFilesView
                        .transition(WorkbenchMotion.workingTreeSectionTransition(usesReducedMotion: reduceMotion))
                } else {
                    WorkingTreeDiffTreeView(
                        files: files,
                        actionIcon: actionIcon,
                        selectedItemID: selectedItemID,
                        onSelect: onSelect,
                        onStageToggle: onStageToggle,
                        onOpen: onOpen,
                        onDiscard: onDiscard,
                        onReveal: onReveal,
                        allDirectoriesExpanded: $allDirectoriesExpanded,
                        directoryExpansionOverrides: $directoryExpansionOverrides,
                        matchedGeometryNamespace: matchedGeometryNamespace,
                        matchedGeometryPaths: matchedGeometryPaths,
                        matchedGeometrySectionID: matchedGeometrySectionID
                    )
                    .transition(WorkbenchMotion.workingTreeSectionTransition(usesReducedMotion: reduceMotion))
                }
            }
        }
    }

    private var stagedEmptyStateView: some View {
        HStack {
            Spacer(minLength: 0)
            Text("No staged files")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, WorkbenchMetrics.sectionSpacing)
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .background(
            RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius)
                .strokeBorder(
                    WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
    }

    private var flatFilesView: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            ForEach(files, id: \.visualID) { adapter in
                let row = WorkingTreeDiffTreeFileRowView(
                    name: adapter.file.fileName,
                    path: adapter.file.path,
                    depth: 0,
                    showsChevronSpacer: false,
                    stat: DiffTreeStat(
                        additions: adapter.file.lineDiff.added,
                        deletions: adapter.file.lineDiff.removed
                    ),
                    file: adapter.file,
                    actionIcon: actionIcon,
                    actionHelp: adapter.actions.primaryLabel,
                    actionAccessibilityLabel: adapter.actions.accessibilityLabel,
                    isSelected: selectedItemID == adapter.id,
                    onSelect: { onSelect(adapter.id) },
                    onAction: { onStageToggle(adapter.file.path) },
                    onOpen: { onOpen(adapter.file.path) },
                    onDiscard: adapter.actions.canDiscard
                        ? {
                            onSelect(adapter.id)
                            onDiscard(adapter.file.path, adapter.file.status)
                        } : nil,
                    onReveal: { onReveal(adapter.file.path) },
                    isFlatMode: true
                )
                if let namespace = matchedGeometryNamespace {
                    row
                        .matchedGeometryEffect(
                            id: matchedGeometryID(for: adapter.file.path),
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
    }

    private func matchedGeometryID(for path: String) -> String {
        guard !reduceMotion, matchedGeometryPaths.contains(path) else {
            return "\(matchedGeometrySectionID):\(path)"
        }
        return path
    }

    private var showsDirectoryControls: Bool {
        displayMode == .tree && !isCollapsed && files.contains { !$0.file.directoryPath.isEmpty }
    }

    private func toggleAllDirectories() {
        allDirectoriesExpanded.toggle()
        directoryExpansionOverrides = [:]
    }
}

#Preview("Staged Section") {
    WorkingTreeSectionView(
        title: "Staged",
        summary: WorkingTreeSectionSummary(fileCount: 3, addedLineCount: 37, removedLineCount: 11),
        files: [
            WorkingTreeRowAdapter.staged(file: WorkingTreeFile(
                path: "GitMenuBar/Pages/MainMenu/MainMenuContent.swift",
                lineDiff: LineDiffStats(added: 23, removed: 8),
                status: .modified
            )),
            WorkingTreeRowAdapter.staged(file: WorkingTreeFile(
                path: "GitMenuBar/Pages/MainMenu/MainMenuView.swift",
                lineDiff: LineDiffStats(added: 5, removed: 2),
                status: .modified
            )),
            WorkingTreeRowAdapter.staged(file: WorkingTreeFile(
                path: "GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift",
                lineDiff: LineDiffStats(added: 9, removed: 1),
                status: .modified
            ))
        ],
        isCollapsed: .constant(false),
        displayMode: .constant(.tree),
        matchedGeometryNamespace: nil,
        matchedGeometryPaths: [],
        matchedGeometrySectionID: "staged",
        selectedItemID: nil,
        onSelect: { _ in },
        onStageToggle: { _ in },
        onOpen: { _ in },
        onDiscard: { _, _ in },
        onReveal: { _ in },
        onAction: {},
        onDiscardAll: nil,
        actionIcon: "minus.circle",
        actionHelp: "Unstage all staged changes"
    )
    .padding()
    .frame(width: 380)
}

#Preview("Staged Section — Empty") {
    WorkingTreeSectionView(
        title: "Staged",
        summary: WorkingTreeSectionSummary(fileCount: 0, addedLineCount: 0, removedLineCount: 0),
        files: [],
        isCollapsed: .constant(false),
        displayMode: .constant(.tree),
        matchedGeometryNamespace: nil,
        matchedGeometryPaths: [],
        matchedGeometrySectionID: "staged",
        selectedItemID: nil,
        onSelect: { _ in },
        onStageToggle: { _ in },
        onOpen: { _ in },
        onDiscard: { _, _ in },
        onReveal: { _ in },
        onAction: {},
        onDiscardAll: nil,
        actionIcon: "minus.circle",
        actionHelp: "Unstage all staged changes",
        showsEmptyState: true
    )
    .padding()
    .frame(width: 380)
}

#Preview("Unstaged Section — Nested Paths") {
    WorkingTreeSectionView(
        title: "Unstaged",
        summary: WorkingTreeSectionSummary(fileCount: 4, addedLineCount: 52, removedLineCount: 14),
        files: [
            WorkingTreeRowAdapter.unstaged(file: WorkingTreeFile(
                path: "GitMenuBar/Services/Git/GitManager.swift",
                lineDiff: LineDiffStats(added: 19, removed: 4),
                status: .modified
            )),
            WorkingTreeRowAdapter.unstaged(file: WorkingTreeFile(
                path: "GitMenuBar/Resources/PreviewSeed.json",
                lineDiff: LineDiffStats(added: 0, removed: 0),
                status: .untracked
            )),
            WorkingTreeRowAdapter.unstaged(file: WorkingTreeFile(
                path: "GitMenuBar/Features/Auth/TokenStore.swift",
                lineDiff: LineDiffStats(added: 12, removed: 3),
                status: .modified
            )),
            WorkingTreeRowAdapter.unstaged(file: WorkingTreeFile(
                path: "GitMenuBar/Features/Auth/Keychain.swift",
                lineDiff: LineDiffStats(added: 21, removed: 7),
                status: .modified
            ))
        ],
        isCollapsed: .constant(false),
        displayMode: .constant(.tree),
        matchedGeometryNamespace: nil,
        matchedGeometryPaths: [],
        matchedGeometrySectionID: "unstaged",
        selectedItemID: .unstagedFile(path: "GitMenuBar/Services/Git/GitManager.swift"),
        onSelect: { _ in },
        onStageToggle: { _ in },
        onOpen: { _ in },
        onDiscard: { _, _ in },
        onReveal: { _ in },
        onAction: {},
        onDiscardAll: {},
        actionIcon: "plus.circle",
        actionHelp: "Stage all unstaged changes",
        showsViewModeToggle: true
    )
    .padding()
    .frame(width: 380)
}
