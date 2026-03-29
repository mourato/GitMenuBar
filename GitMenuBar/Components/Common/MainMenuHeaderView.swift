import AppKit
import SwiftUI

struct MainMenuHeaderView<PopoverContent: View, ContextMenuContent: View, RepoOptionsContent: View>: View {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    @Binding var showRepositoryOptionsPopover: Bool
    let showsRepositoryOptionsButton: Bool
    let onShowRepositoryOptions: () -> Void
    let projectSelectorContent: () -> PopoverContent
    let projectContextMenu: () -> ContextMenuContent
    let repositoryOptionsContent: () -> RepoOptionsContent

    @State private var isProjectHovered = false
    @State private var isRepositoryOptionsHovered = false

    init(
        currentProjectName: String,
        showProjectSelector: Binding<Bool>,
        showRepositoryOptionsPopover: Binding<Bool>,
        showsRepositoryOptionsButton: Bool,
        onShowRepositoryOptions: @escaping () -> Void,
        @ViewBuilder projectSelectorContent: @escaping () -> PopoverContent,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent,
        @ViewBuilder repositoryOptionsContent: @escaping () -> RepoOptionsContent
    ) {
        self.currentProjectName = currentProjectName
        _showProjectSelector = showProjectSelector
        _showRepositoryOptionsPopover = showRepositoryOptionsPopover
        self.showsRepositoryOptionsButton = showsRepositoryOptionsButton
        self.onShowRepositoryOptions = onShowRepositoryOptions
        self.projectSelectorContent = projectSelectorContent
        self.projectContextMenu = projectContextMenu
        self.repositoryOptionsContent = repositoryOptionsContent
    }

    var body: some View {
        HStack(spacing: MacChromeMetrics.compactSpacing) {
            Button(action: { showProjectSelector.toggle() }, label: {
                HStack(spacing: 6) {
                    Text(currentProjectName)
                        .font(MacChromeTypography.windowTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(MacChromeTypography.captionStrong)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous)
                        .fill(isProjectHovered ? MacChromePalette.hoverFill() : Color.clear)
                )
            })
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .controlSize(.small)
            .accessibilityLabel("Current repository")
            .accessibilityHint("Opens the recent repository picker.")
            .onHover { inside in
                isProjectHovered = inside
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .contextMenu(menuItems: projectContextMenu)
            .popover(isPresented: $showProjectSelector) {
                projectSelectorContent()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsRepositoryOptionsButton {
                Button {
                    onShowRepositoryOptions()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(MacChromeTypography.body)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous)
                                .fill(isRepositoryOptionsHovered ? MacChromePalette.hoverFill() : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .accessibilityLabel("Repository options")
                .accessibilityHint("Shows repository visibility and deletion actions.")
                .onHover { inside in
                    isRepositoryOptionsHovered = inside
                }
                .popover(isPresented: $showRepositoryOptionsPopover, arrowEdge: .top) {
                    repositoryOptionsContent()
                }
            }
        }
    }
}

#Preview("Main Menu Header") {
    MainMenuHeaderView(
        currentProjectName: "gitmenubar",
        showProjectSelector: .constant(false),
        showRepositoryOptionsPopover: .constant(false),
        showsRepositoryOptionsButton: true,
        onShowRepositoryOptions: {},
        projectSelectorContent: {
            Text("Projects")
                .padding()
        },
        projectContextMenu: {
            Button("Repository Options…") {}
        },
        repositoryOptionsContent: {
            RepositoryOptionsPopoverView(
                visibilityStatusDescription: "This repository is currently private.",
                visibilityActionTitle: "Make Public",
                onToggleVisibility: {},
                onDeleteRepository: {}
            )
        }
    )
    .padding()
    .frame(width: 400)
}
