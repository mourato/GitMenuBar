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
                onDiscardAll: onDiscardAll
            )

            if !isCollapsed {
                VStack(spacing: 3) {
                    ForEach(files) { row in
                        WorkingTreeFileRowView(
                            file: row.file,
                            actionIcon: actionIcon,
                            actionHelp: row.actions.primaryLabel,
                            isSelected: selectedItemID == row.id,
                            onSelect: {
                                onSelect(row.id)
                            },
                            onAction: { onStageToggle(row.file.path) },
                            onOpen: { onOpen(row.file.path) },
                            onDiscard: {
                                onSelect(row.id)
                                onDiscard(row.file.path, row.file.status)
                            },
                            onReveal: { onReveal(row.file.path) }
                        )
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview("Staged Section") {
    WorkingTreeSectionView(
        title: "Staged",
        summary: WorkingTreeSectionSummary(fileCount: 2, addedLineCount: 28, removedLineCount: 10),
        files: [
            WorkingTreeRowAdapter.staged(file: WorkingTreeFile(
                path: "GitMenuBar/Features/MainMenu/MainMenuContent.swift",
                lineDiff: LineDiffStats(added: 23, removed: 8),
                status: .modified
            )),
            WorkingTreeRowAdapter.staged(file: WorkingTreeFile(
                path: "GitMenuBar/Features/MainMenu/MainMenuView.swift",
                lineDiff: LineDiffStats(added: 5, removed: 2),
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
