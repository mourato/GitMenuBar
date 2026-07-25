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

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(
                    WorkbenchMotion.adaptive(WorkbenchMotion.settle, usesReducedMotion: reduceMotion)
                ) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundColor(.secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))

                    Text(title)
                        .font(WorkbenchTypography.body)
                        .tracking(WorkbenchTypography.tracking(for: .subheadline))
                }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("\(title) section")
            .accessibilityHint(isCollapsed ? "Expands the section." : "Collapses the section.")

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                WorkingTreeLineDiffView(
                    addedCount: summary.addedLineCount,
                    removedCount: summary.removedLineCount
                )

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
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
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
    }
}

private struct WorkingTreeSectionHeaderPreviewContainer: View {
    @State private var isCollapsed = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private let previewFiles = [
        WorkingTreeFile(
            path: "GitMenuBar/Pages/MainMenu/MainMenuContent.swift",
            lineDiff: LineDiffStats(added: 23, removed: 8),
            status: .modified
        ),
        WorkingTreeFile(
            path: "GitMenuBar/Services/Git/GitManager.swift",
            lineDiff: LineDiffStats(added: 19, removed: 4),
            status: .modified
        ),
        WorkingTreeFile(
            path: "GitMenuBar/Resources/PreviewSeed.json",
            lineDiff: LineDiffStats(added: 0, removed: 0),
            status: .untracked
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkingTreeSectionHeaderView(
                title: "Staged",
                summary: previewFiles.sectionSummary,
                isCollapsed: $isCollapsed,
                actionIcon: "minus.circle",
                actionHelp: "Unstage all files",
                showsAction: true,
                onAction: {},
                onDiscardAll: {}
            )

            if !isCollapsed {
                VStack(spacing: 3) {
                    ForEach(previewFiles) { file in
                        WorkingTreeFileRowView(
                            file: file,
                            actionIcon: "minus.circle",
                            actionHelp: "Unstage file",
                            onAction: {},
                            onOpen: {},
                            onDiscard: {},
                            onReveal: {}
                        )
                    }
                }
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
