import Combine
import SwiftUI

struct MainMenuShellView<Detail: View, SidePanel: View>: View {
    let currentRepositoryPath: String
    let onSelectRepository: (String) -> Void
    let onReveal: (String) -> Void
    let onStopMonitoring: (String) -> Void
    let onRemove: (String) -> Void
    let onRename: (String, String) -> Void
    let onProjectCleanup: () -> Void
    let onAddProject: () -> Void
    let onRefreshAll: () -> Void
    let onFetchAll: () -> Void
    let onOpenSettings: () -> Void
    var sidebarVisibility: Binding<NavigationSplitViewVisibility>
    @ViewBuilder let detail: Detail
    var sidePanelPresented: Binding<Bool>
    let dismissSidePanelOnOutsideTap: Bool
    @ViewBuilder let sidePanel: SidePanel
    let onExitCommand: () -> Void
    let shortcutActions: PassthroughSubject<MainMenuShortcutAction, Never>
    let onShortcutAction: (MainMenuShortcutAction) -> Void

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            ProjectsSidebarView(
                currentPath: currentRepositoryPath,
                onSelect: onSelectRepository,
                onReveal: onReveal,
                onStopMonitoring: onStopMonitoring,
                onRemove: onRemove,
                onRename: onRename,
                onProjectCleanup: onProjectCleanup,
                onAddProject: onAddProject,
                onRefreshAll: onRefreshAll,
                onFetchAll: onFetchAll,
                onOpenSettings: onOpenSettings
            )
            .navigationSplitViewColumnWidth(
                min: WorkbenchMetrics.projectsMinimumWidth,
                ideal: WorkbenchMetrics.projectsMinimumWidth,
                max: WorkbenchMetrics.projectsMaximumWidth
            )
        } detail: {
            detail
                .padding(.leading, WorkbenchMetrics.windowPadding)
                .padding(.trailing, WorkbenchMetrics.windowPadding)
                .padding(.bottom, WorkbenchMetrics.windowPadding)
                .frame(
                    minWidth: WorkbenchMetrics.centralMinimumWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .sidePanel(
                    isPresented: sidePanelPresented,
                    dismissOnOutsideTap: dismissSidePanelOnOutsideTap
                ) {
                    sidePanel
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onExitCommand(perform: onExitCommand)
        .onReceive(shortcutActions, perform: onShortcutAction)
    }
}

#Preview("Shell") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        ShellPreviewContent()
    }
}

private struct ShellPreviewContent: View {
    @State private var isSidebarCollapsed = false
    @State private var isSidePanelPresented = false
    private let shortcutActions = PassthroughSubject<MainMenuShortcutAction, Never>()

    var body: some View {
        MainMenuShellView(
            currentRepositoryPath: "/tmp/demo",
            onSelectRepository: { _ in },
            onReveal: { _ in },
            onStopMonitoring: { _ in },
            onRemove: { _ in },
            onRename: { _, _ in },
            onProjectCleanup: {},
            onAddProject: {},
            onRefreshAll: {},
            onFetchAll: {},
            onOpenSettings: {},
            sidebarVisibility: Binding(
                get: { isSidebarCollapsed ? .detailOnly : .all },
                set: { isSidebarCollapsed = $0 == .detailOnly }
            ),
            detail: {
                Text("Detail")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            },
            sidePanelPresented: $isSidePanelPresented,
            dismissSidePanelOnOutsideTap: true,
            sidePanel: {
                Text("Side panel")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            },
            onExitCommand: {},
            shortcutActions: shortcutActions,
            onShortcutAction: { _ in }
        )
    }
}
