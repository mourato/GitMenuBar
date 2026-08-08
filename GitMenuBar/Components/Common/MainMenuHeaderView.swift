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
        case .projectCleanup:
            projectCleanupHeader {
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

    private func projectCleanupHeader(onBack: @escaping () -> Void) -> some View {
        ZStack {
            Text("Project Cleanup")
                .font(WorkbenchTypography.windowTitle)
                .accessibilityAddTraits(.isHeader)
            HStack {
                MainMenuHeaderIconButton(
                    systemImage: "chevron.backward",
                    accessibilityLabel: "Back",
                    accessibilityHint: "Returns to the main repository view.",
                    action: onBack
                )
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview("Main Menu Header Chrome") {
    MainMenuPreviewHarness(width: 700, showsTransparentTitlebar: true) {
        MainMenuView()
            .frame(height: 96)
            .clipped()
    }
}
