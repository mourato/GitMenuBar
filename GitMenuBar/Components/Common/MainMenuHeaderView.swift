import SwiftUI

extension MainMenuView {
    @ViewBuilder
    var routeHeaderContent: some View {
        switch presentationModel.route {
        case .main, .createRepo:
            mainContentHeader
        case .historyDetail:
            commitDetailHeader {
                dismissTransientPresentations()
                presentationModel.showMain()
            }
        }
    }

    var windowHeaderLeadingControls: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            MainMenuHeaderIconButton(
                systemImage: isProjectsSidebarCollapsed ? "sidebar.right" : "sidebar.left",
                accessibilityLabel: isProjectsSidebarCollapsed ? "Expand Projects sidebar" : "Collapse Projects sidebar",
                accessibilityHint: "Shows or hides the Projects sidebar.",
                action: toggleProjectsSidebar
            )
            MainMenuHeaderIconButton(
                systemImage: "plus",
                accessibilityLabel: "Add Project",
                accessibilityHint: "Choose a local Git repository to monitor.",
                action: selectDirectory
            )
            MainMenuHeaderIconButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: "Refresh All Projects",
                accessibilityHint: "Refreshes the Git status for every monitored project.",
                action: projectMonitor.refreshAll
            )
            MainMenuHeaderIconButton(
                systemImage: "arrow.down.circle",
                accessibilityLabel: "Fetch All Projects",
                accessibilityHint: "Fetches remotes for every monitored project.",
                action: projectMonitor.fetchAll
            )
        }
        .padding(.leading, ProjectsSidebarMetrics.sidebarToggleLeadingPadding)
    }

    private var mainContentHeader: some View {
        ZStack {
            Text(currentProjectName)
                .font(WorkbenchTypography.windowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
                .contextMenu {
                    if canPresentRepositoryOptions {
                        Button("Repository options") {
                            requestRepositoryOptionsPopoverPresentation()
                        }
                    }
                }

            HStack {
                Spacer(minLength: 0)
                MainMenuHeaderIconButton(
                    systemImage: "gearshape",
                    accessibilityLabel: "Settings",
                    accessibilityHint: "Opens GitMenuBar settings.",
                    action: {
                        dismissTransientPresentations()
                        openSettingsWindow()
                    }
                )
                .disabled(isCommandPalettePresented)
                .opacity(isCommandPalettePresented ? 0.5 : 1)
            }
        }
    }

    private func commitDetailHeader(onBack: @escaping () -> Void) -> some View {
        ZStack {
            Text("Commit Details")
                .font(WorkbenchTypography.windowTitle)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            HStack {
                MainMenuHeaderIconButton(
                    systemImage: "chevron.backward",
                    accessibilityLabel: "Back",
                    accessibilityHint: "Returns to the main repository view.",
                    action: onBack
                )

                Spacer(minLength: 0)

                MainMenuHeaderIconButton(
                    systemImage: "gearshape",
                    accessibilityLabel: "Settings",
                    accessibilityHint: "Opens GitMenuBar settings.",
                    action: {
                        dismissTransientPresentations()
                        openSettingsWindow()
                    }
                )
            }
        }
    }
}
