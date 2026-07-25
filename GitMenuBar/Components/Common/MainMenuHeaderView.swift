import AppKit
import SwiftUI

struct MainMenuProjectSelectorControl<PopoverContent: View, ContextMenuContent: View, RepoOptionsContent: View>: View {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    @Binding var showRepositoryOptionsPopover: Bool
    let projectSelectorContent: () -> PopoverContent
    let projectContextMenu: () -> ContextMenuContent
    let repositoryOptionsContent: () -> RepoOptionsContent

    @State private var isProjectHovered = false

    init(
        currentProjectName: String,
        showProjectSelector: Binding<Bool>,
        showRepositoryOptionsPopover: Binding<Bool>,
        @ViewBuilder projectSelectorContent: @escaping () -> PopoverContent,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent,
        @ViewBuilder repositoryOptionsContent: @escaping () -> RepoOptionsContent
    ) {
        self.currentProjectName = currentProjectName
        _showProjectSelector = showProjectSelector
        _showRepositoryOptionsPopover = showRepositoryOptionsPopover
        self.projectSelectorContent = projectSelectorContent
        self.projectContextMenu = projectContextMenu
        self.repositoryOptionsContent = repositoryOptionsContent
    }

    var body: some View {
        Button(action: { showProjectSelector.toggle() }, label: {
            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                Text(currentProjectName)
                    .font(WorkbenchTypography.windowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .fill(isProjectHovered ? WorkbenchPalette.hoverFill() : Color.clear)
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
        .popover(isPresented: $showRepositoryOptionsPopover, arrowEdge: .top) {
            repositoryOptionsContent()
        }
    }
}

struct MainMenuHeaderToolbarContent<PopoverContent: View, ContextMenuContent: View, RepoOptionsContent: View>: ToolbarContent {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    @Binding var showRepositoryOptionsPopover: Bool
    let onOpenSettings: () -> Void
    let projectSelectorContent: () -> PopoverContent
    let projectContextMenu: () -> ContextMenuContent
    let repositoryOptionsContent: () -> RepoOptionsContent

    init(
        currentProjectName: String,
        showProjectSelector: Binding<Bool>,
        showRepositoryOptionsPopover: Binding<Bool>,
        onOpenSettings: @escaping () -> Void,
        @ViewBuilder projectSelectorContent: @escaping () -> PopoverContent,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent,
        @ViewBuilder repositoryOptionsContent: @escaping () -> RepoOptionsContent
    ) {
        self.currentProjectName = currentProjectName
        _showProjectSelector = showProjectSelector
        _showRepositoryOptionsPopover = showRepositoryOptionsPopover
        self.onOpenSettings = onOpenSettings
        self.projectSelectorContent = projectSelectorContent
        self.projectContextMenu = projectContextMenu
        self.repositoryOptionsContent = repositoryOptionsContent
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            MainMenuProjectSelectorControl(
                currentProjectName: currentProjectName,
                showProjectSelector: $showProjectSelector,
                showRepositoryOptionsPopover: $showRepositoryOptionsPopover,
                projectSelectorContent: projectSelectorContent,
                projectContextMenu: projectContextMenu,
                repositoryOptionsContent: repositoryOptionsContent
            )
        }

        ToolbarItem(placement: .primaryAction) {
            MainMenuHeaderIconButton(
                systemImage: "gearshape",
                accessibilityLabel: "Settings",
                accessibilityHint: "Opens GitMenuBar settings.",
                action: onOpenSettings
            )
        }
    }
}

#Preview("Main Menu Project Selector") {
    MainMenuProjectSelectorControl(
        currentProjectName: "gitmenubar",
        showProjectSelector: .constant(false),
        showRepositoryOptionsPopover: .constant(false),
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

#Preview("Main Menu Header Toolbar") {
    NavigationStack {
        Text("Main menu content")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                MainMenuHeaderToolbarContent(
                    currentProjectName: "gitmenubar",
                    showProjectSelector: .constant(false),
                    showRepositoryOptionsPopover: .constant(false),
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
            }
    }
    .frame(width: 400, height: 240)
}
