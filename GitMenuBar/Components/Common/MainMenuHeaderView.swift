import AppKit
import SwiftUI

struct MainMenuProjectSelectorControl<PopoverContent: View, ContextMenuContent: View>: View {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    let isInteractionDisabled: Bool
    let projectSelectorContent: () -> PopoverContent
    let projectContextMenu: () -> ContextMenuContent

    @State private var isProjectHovered = false

    init(
        currentProjectName: String,
        showProjectSelector: Binding<Bool>,
        isInteractionDisabled: Bool = false,
        @ViewBuilder projectSelectorContent: @escaping () -> PopoverContent,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent
    ) {
        self.currentProjectName = currentProjectName
        _showProjectSelector = showProjectSelector
        self.isInteractionDisabled = isInteractionDisabled
        self.projectSelectorContent = projectSelectorContent
        self.projectContextMenu = projectContextMenu
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
        .disabled(isInteractionDisabled)
        .opacity(isInteractionDisabled ? 0.5 : 1)
        .accessibilityLabel("Current repository")
        .accessibilityHint("Opens the recent repository picker.")
        .onHover { inside in
            guard !isInteractionDisabled else { return }
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
    }
}

struct MainMenuHeaderToolbarContent<PopoverContent: View, ContextMenuContent: View, RepoOptionsContent: View>: ToolbarContent {
    let currentProjectName: String
    @Binding var showProjectSelector: Bool
    @Binding var showRepositoryOptionsPopover: Bool
    let isCommandPalettePresented: Bool
    let onOpenSettings: () -> Void
    let projectSelectorContent: () -> PopoverContent
    let projectContextMenu: () -> ContextMenuContent
    let repositoryOptionsContent: () -> RepoOptionsContent

    init(
        currentProjectName: String,
        showProjectSelector: Binding<Bool>,
        showRepositoryOptionsPopover: Binding<Bool>,
        isCommandPalettePresented: Bool,
        onOpenSettings: @escaping () -> Void,
        @ViewBuilder projectSelectorContent: @escaping () -> PopoverContent,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent,
        @ViewBuilder repositoryOptionsContent: @escaping () -> RepoOptionsContent
    ) {
        self.currentProjectName = currentProjectName
        _showProjectSelector = showProjectSelector
        _showRepositoryOptionsPopover = showRepositoryOptionsPopover
        self.isCommandPalettePresented = isCommandPalettePresented
        self.onOpenSettings = onOpenSettings
        self.projectSelectorContent = projectSelectorContent
        self.projectContextMenu = projectContextMenu
        self.repositoryOptionsContent = repositoryOptionsContent
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 0) {
                MainMenuProjectSelectorControl(
                    currentProjectName: currentProjectName,
                    showProjectSelector: $showProjectSelector,
                    isInteractionDisabled: isCommandPalettePresented,
                    projectSelectorContent: projectSelectorContent,
                    projectContextMenu: projectContextMenu
                )

                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .popover(isPresented: $showRepositoryOptionsPopover, arrowEdge: .top) {
                        repositoryOptionsContent()
                    }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            MainMenuHeaderIconButton(
                systemImage: "gearshape",
                accessibilityLabel: "Settings",
                accessibilityHint: "Opens GitMenuBar settings.",
                action: onOpenSettings
            )
            .disabled(isCommandPalettePresented)
            .opacity(isCommandPalettePresented ? 0.5 : 1)
        }
    }
}

/// Titlebar toolbar for the Commit Details route — same chrome slots as main (principal + trailing).
struct CommitDetailHeaderToolbarContent: ToolbarContent {
    let onBack: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Commit Details")
                .font(WorkbenchTypography.windowTitle)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }

        ToolbarItem(placement: .primaryAction) {
            MainMenuHeaderIconButton(
                systemImage: "chevron.backward",
                accessibilityLabel: "Back",
                accessibilityHint: "Returns to the main repository view.",
                action: onBack
            )
        }
    }
}

#Preview("Main Menu Project Selector") {
    MainMenuProjectSelectorControl(
        currentProjectName: "gitmenubar",
        showProjectSelector: .constant(false),
        projectSelectorContent: {
            Text("Projects")
                .padding()
        },
        projectContextMenu: {
            Button("Repository options") {}
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
                    isCommandPalettePresented: false,
                    onOpenSettings: {},
                    projectSelectorContent: {
                        Text("Projects")
                            .padding()
                    },
                    projectContextMenu: {
                        Button("Repository options") {}
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

#Preview("Commit Detail Header Toolbar") {
    NavigationStack {
        Text("Commit detail content")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                CommitDetailHeaderToolbarContent(onBack: {})
            }
    }
    .frame(width: 400, height: 240)
}
