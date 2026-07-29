import AppKit
import SwiftUI

struct MainMenuProjectSelectorControl<ContextMenuContent: View>: View {
    let currentProjectName: String
    let isProjectSelectorPresented: Bool
    let isInteractionDisabled: Bool
    let onToggleProjectSelector: () -> Void
    let projectContextMenu: () -> ContextMenuContent

    @State private var isProjectHovered = false

    init(
        currentProjectName: String,
        isProjectSelectorPresented: Bool,
        isInteractionDisabled: Bool = false,
        onToggleProjectSelector: @escaping () -> Void,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent
    ) {
        self.currentProjectName = currentProjectName
        self.isProjectSelectorPresented = isProjectSelectorPresented
        self.isInteractionDisabled = isInteractionDisabled
        self.onToggleProjectSelector = onToggleProjectSelector
        self.projectContextMenu = projectContextMenu
    }

    var body: some View {
        Button(action: onToggleProjectSelector, label: {
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
        .accessibilityValue(isProjectSelectorPresented ? "Projects sidebar open" : "Projects sidebar closed")
        .accessibilityHint("Shows the Projects sidebar.")
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
    }
}

struct MainMenuHeaderToolbarContent<ContextMenuContent: View>: ToolbarContent {
    let currentProjectName: String
    let isProjectSelectorPresented: Bool
    let isCommandPalettePresented: Bool
    let onToggleProjectSelector: () -> Void
    let onOpenSettings: () -> Void
    let projectContextMenu: () -> ContextMenuContent

    init(
        currentProjectName: String,
        isProjectSelectorPresented: Bool,
        isCommandPalettePresented: Bool = false,
        onToggleProjectSelector: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        @ViewBuilder projectContextMenu: @escaping () -> ContextMenuContent
    ) {
        self.currentProjectName = currentProjectName
        self.isProjectSelectorPresented = isProjectSelectorPresented
        self.isCommandPalettePresented = isCommandPalettePresented
        self.onToggleProjectSelector = onToggleProjectSelector
        self.onOpenSettings = onOpenSettings
        self.projectContextMenu = projectContextMenu
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            MainMenuProjectSelectorControl(
                currentProjectName: currentProjectName,
                isProjectSelectorPresented: isProjectSelectorPresented,
                isInteractionDisabled: isCommandPalettePresented,
                onToggleProjectSelector: onToggleProjectSelector,
                projectContextMenu: projectContextMenu
            )
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
        isProjectSelectorPresented: false,
        onToggleProjectSelector: {},
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
                    isProjectSelectorPresented: false,
                    isCommandPalettePresented: false,
                    onToggleProjectSelector: {},
                    onOpenSettings: {},
                    projectContextMenu: {
                        Button("Repository options") {}
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
