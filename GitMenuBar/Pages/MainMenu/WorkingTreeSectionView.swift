import SwiftUI

struct WorkingTreeSectionView: View {
    let title: String
    let summary: WorkingTreeSectionSummary
    let files: [WorkingTreeRowAdapter]
    @Binding var isCollapsed: Bool
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

    private var showsDirectoryControls: Bool {
        !isCollapsed && diffTreeViewShowsDirectoryControls
    }

    private var diffTreeViewShowsDirectoryControls: Bool {
        let treeNodes = DiffTreeBuilder.buildDiffTree(files.map(\.file.diffTreeFileInput))
        return !Self.collectDirectoryPaths(in: treeNodes).isEmpty
    }

    private func toggleAllDirectories() {
        allDirectoriesExpanded.toggle()
        directoryExpansionOverrides = [:]
    }

    private static func collectDirectoryPaths(in nodes: [DiffTreeNode]) -> [String] {
        nodes.flatMap { node -> [String] in
            switch node {
            case let .directory(_, path, _, children):
                return [path] + collectDirectoryPaths(in: children)
            case .file:
                return []
            }
        }
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
