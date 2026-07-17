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
                    MacChromeMotion.adaptive(MacChromeMotion.settle, usesReducedMotion: reduceMotion)
                ) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(MacChromeTypography.captionStrong)
                        .foregroundColor(.secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))

                    Text(title)
                        .font(MacChromeTypography.body)
                }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("\(title) section")
            .accessibilityHint(isCollapsed ? "Expands the section." : "Collapses the section.")

            Spacer(minLength: 8)

            ZStack(alignment: .trailing) {
                WorkingTreeLineDiffView(
                    addedCount: summary.addedLineCount,
                    removedCount: summary.removedLineCount
                )
                .opacity(isHovered && showsAction ? 0 : 1)

                HStack(spacing: 4) {
                    if let onDiscardAll {
                        Button(action: onDiscardAll) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(MacChromeTypography.captionStrong)
                                .foregroundColor(.primary)
                                .frame(width: WorkingTreeLayoutMetrics.actionWidth, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .help("Discard All")
                        .accessibilityLabel("Discard all files in \(title)")
                    }

                    Button(action: onAction) {
                        Image(systemName: actionIcon)
                            .font(MacChromeTypography.captionStrong)
                            .foregroundColor(.primary)
                            .frame(width: WorkingTreeLayoutMetrics.actionWidth, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help(actionHelp)
                    .accessibilityLabel(actionHelp)
                }
                .opacity(isHovered && showsAction ? 1 : 0)
                .allowsHitTesting(isHovered && showsAction)
            }

            Text(summary.fileCountText)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(
                    MacChromeMotion.adaptive(MacChromeMotion.swap, usesReducedMotion: reduceMotion),
                    value: summary.fileCount
                )
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHovered ? MacChromePalette.hoverFill() : Color.clear)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    MacChromePalette.neutralBorder(contrast: colorSchemeContrast)
                        .opacity(colorSchemeContrast == .increased ? 1 : 0),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .animation(
            MacChromeMotion.adaptive(MacChromeMotion.micro, usesReducedMotion: reduceMotion),
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
