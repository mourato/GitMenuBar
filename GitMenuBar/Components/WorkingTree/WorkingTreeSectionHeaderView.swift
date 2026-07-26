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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WorkbenchSectionHeaderChrome(
            title: title,
            isCollapsed: $isCollapsed,
            accessibilityLabel: "\(title) section",
            accessibilityHintExpanded: "Expands the section.",
            accessibilityHintCollapsed: "Collapses the section."
        ) { isHovered in
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                HStack(spacing: WorkbenchMetrics.microSpacing) {
                    WorkingTreeLineDiffView(
                        addedCount: summary.addedLineCount,
                        removedCount: summary.removedLineCount
                    )

                    if showsDirectoryControls, let onToggleAllDirectories {
                        Button(action: onToggleAllDirectories) {
                            Image(
                                systemName: allDirectoriesExpanded
                                    ? "arrow.down.right.and.arrow.up.left"
                                    : "arrow.up.left.and.arrow.down.right"
                            )
                            .font(WorkbenchTypography.captionStrong)
                            .foregroundColor(.primary)
                            .frame(
                                width: WorkingTreeLayoutMetrics.actionHitTarget,
                                height: WorkingTreeLayoutMetrics.actionHitTarget
                            )
                            .contentShape(Rectangle())
                        }
                        .workbenchIcon()
                        .help(allDirectoriesExpanded ? "Collapse all folders" : "Expand all folders")
                        .accessibilityLabel(allDirectoriesExpanded ? "Collapse all folders" : "Expand all folders")
                        .opacity(isHovered ? 1 : 0)
                        .allowsHitTesting(isHovered)
                    }

                    if showsAction {
                        if let onDiscardAll {
                            Button(action: onDiscardAll) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(WorkbenchTypography.captionStrong)
                                    .foregroundColor(.primary)
                                    .frame(
                                        width: WorkingTreeLayoutMetrics.actionHitTarget,
                                        height: WorkingTreeLayoutMetrics.actionHitTarget
                                    )
                                    .contentShape(Rectangle())
                            }
                            .workbenchIcon()
                            .help("Discard All")
                            .accessibilityLabel("Discard all files in \(title)")
                            .opacity(isHovered ? 1 : 0)
                            .allowsHitTesting(isHovered)
                        }

                        Button(action: onAction) {
                            Image(systemName: actionIcon)
                                .font(WorkbenchTypography.captionStrong)
                                .foregroundColor(.primary)
                                .frame(
                                    width: WorkingTreeLayoutMetrics.actionHitTarget,
                                    height: WorkingTreeLayoutMetrics.actionHitTarget
                                )
                                .contentShape(Rectangle())
                        }
                        .workbenchIcon()
                        .help(actionHelp)
                        .accessibilityLabel("\(actionHelp) in \(title)")
                    }
                }

                Text(summary.fileCountText)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(
                        WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                        value: summary.fileCount
                    )
            }
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
                actionHelp: "Unstage all files",
                showsAction: true,
                onAction: {},
                onDiscardAll: {},
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

#Preview("Unstaged Section Header — Stage All Visible") {
    struct UnstagedPreview: View {
        @State private var isCollapsed = false

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
                actionHelp: "Stage all files",
                showsAction: true,
                onAction: {},
                onDiscardAll: {}
            )
            .padding()
            .frame(width: 380, alignment: .leading)
        }
    }

    return UnstagedPreview()
}
