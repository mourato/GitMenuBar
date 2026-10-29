import SwiftUI

struct WorkingTreeSectionView: View {
    let title: String
    let summary: WorkingTreeSectionSummary
    let files: [WorkingTreeRowAdapter]
    @Binding var isCollapsed: Bool
    var displayMode: AppPreferences.WorkingTreeDisplayMode = .tree
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                onToggleAllDirectories: toggleAllDirectories
            )

            if !isCollapsed {
                if displayMode == .flat {
                    flatFilesView
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
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
                        directoryExpansionOverrides: $directoryExpansionOverrides
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var flatFilesView: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            ForEach(files) { adapter in
                WorkingTreeDiffTreeFileRowView(
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
            }
        }
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
        selectedItemID: nil,
        onSelect: { _ in },
        onStageToggle: { _ in },
        onOpen: { _ in },
        onDiscard: { _, _ in },
        onReveal: { _ in },
        onAction: {},
        onDiscardAll: nil,
        actionIcon: "minus.circle",
        actionHelp: "Unstage all files"
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
        selectedItemID: .unstagedFile(path: "GitMenuBar/Services/Git/GitManager.swift"),
        onSelect: { _ in },
        onStageToggle: { _ in },
        onOpen: { _ in },
        onDiscard: { _, _ in },
        onReveal: { _ in },
        onAction: {},
        onDiscardAll: {},
        actionIcon: "plus.circle",
        actionHelp: "Stage all files"
    )
    .padding()
    .frame(width: 380)
}
