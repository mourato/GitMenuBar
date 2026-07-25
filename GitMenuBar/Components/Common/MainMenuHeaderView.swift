import AppKit
import SwiftUI

struct MainMenuHeaderView<PopoverContent: View, ContextMenuContent: View, RepoOptionsContent: View>: View {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    @Binding var showRepositoryOptionsPopover: Bool
    let showsRepositoryOptionsButton: Bool
    let onShowRepositoryOptions: () -> Void
    let onOpenSettings: () -> Void
    let projectSelectorContent: () -> PopoverContent
    let projectContextMenu: () -> ContextMenuContent
    let repositoryOptionsContent: () -> RepoOptionsContent

    @State private var isProjectHovered = false

    init(
        currentProjectName: String,
        showProjectSelector: Binding<Bool>,
        showRepositoryOptionsPopover: Binding<Bool>,
        showsRepositoryOptionsButton: Bool,
        onShowRepositoryOptions: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        @ViewBuilder projectSelectorContent: @escaping () -> PopoverContent,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent,
        @ViewBuilder repositoryOptionsContent: @escaping () -> RepoOptionsContent
    ) {
        self.currentProjectName = currentProjectName
        _showProjectSelector = showProjectSelector
        _showRepositoryOptionsPopover = showRepositoryOptionsPopover
        self.showsRepositoryOptionsButton = showsRepositoryOptionsButton
        self.onShowRepositoryOptions = onShowRepositoryOptions
        self.onOpenSettings = onOpenSettings
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
                MainMenuHeaderIconButton(
                    systemImage: "ellipsis.circle",
                    accessibilityLabel: "Repository options",
                    accessibilityHint: "Shows repository visibility and deletion actions.",
                    action: onShowRepositoryOptions
                )
                .popover(isPresented: $showRepositoryOptionsPopover, arrowEdge: .top) {
                    repositoryOptionsContent()
                }
            }

            MainMenuHeaderIconButton(
                systemImage: "gearshape",
                accessibilityLabel: "Settings",
                accessibilityHint: "Opens GitMenuBar settings.",
                action: onOpenSettings
            )
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .macPanelSurface(cornerRadius: MacChromeMetrics.cornerRadius, material: .thin)
    }
}

#Preview("Main Menu Header") {
    return MainMenuHeaderView(
        currentProjectName: "gitmenubar",
        showProjectSelector: .constant(false),
        showRepositoryOptionsPopover: .constant(false),
        showsRepositoryOptionsButton: true,
        onShowRepositoryOptions: {},
        onOpenSettings: {},
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
