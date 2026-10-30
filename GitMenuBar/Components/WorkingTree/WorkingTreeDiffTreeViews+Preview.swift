import SwiftUI

#Preview("Working Tree Diff Tree") {
    struct PreviewContainer: View {
        @State private var allDirectoriesExpanded = true
        @State private var directoryExpansionOverrides: [String: Bool] = [:]

        private let files: [WorkingTreeRowAdapter] = [
            .staged(file: WorkingTreeFile(
                path: "GitMenuBar/Pages/MainMenu/MainMenuContent.swift",
                lineDiff: LineDiffStats(added: 23, removed: 8),
                status: .modified
            )),
            .staged(file: WorkingTreeFile(
                path: "GitMenuBar/Pages/MainMenu/MainMenuView.swift",
                lineDiff: LineDiffStats(added: 5, removed: 2),
                status: .modified
            )),
            .staged(file: WorkingTreeFile(
                path: "GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift",
                lineDiff: LineDiffStats(added: 9, removed: 1),
                status: .modified
            )),
            .staged(file: WorkingTreeFile(
                path: "GitMenuBar/Components/WorkingTree/RemovedFile.swift",
                lineDiff: LineDiffStats(added: 0, removed: 18),
                status: .deleted
            )),
            .staged(file: WorkingTreeFile(
                path: "GitMenuBar/Resources/PreviewSeed.json",
                lineDiff: LineDiffStats(added: 7, removed: 0),
                status: .untracked
            ))
        ]

        var body: some View {
            WorkingTreeDiffTreeView(
                files: files,
                actionIcon: "minus.circle",
                selectedItemID: .stagedFile(path: files[0].file.path),
                onSelect: { _ in },
                onStageToggle: { _ in },
                onOpen: { _ in },
                onDiscard: { _, _ in },
                onReveal: { _ in },
                allDirectoriesExpanded: $allDirectoriesExpanded,
                directoryExpansionOverrides: $directoryExpansionOverrides
            )
            .padding()
            .frame(width: 380)
        }
    }

    return PreviewContainer()
}

#Preview("Working Tree Directory Row") {
    VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
        WorkingTreeDiffTreeDirectoryRowView(
            name: "Pages/MainMenu",
            depth: 1,
            isExpanded: true,
            stat: nil
        )
        WorkingTreeDiffTreeDirectoryRowView(
            name: "Components",
            depth: 0,
            isExpanded: false,
            stat: nil
        )
    }
    .padding()
    .frame(width: 380)
}
