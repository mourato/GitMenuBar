import SwiftUI

struct ProjectsSidebarView: View {
    @Environment(ProjectMonitorStore.self) private var monitor
    @AppStorage(AppPreferences.Keys.showAgentActivity) private var showAgentActivity = true
    @AppStorage(AppPreferences.Keys.isCleanProjectsGroupCollapsed) private var isCleanGroupCollapsed = false
    @State private var renameProject: ProjectReference?
    @State private var renameDraft = ""

    let currentPath: String
    let onSelect: (String) -> Void
    let onReveal: (String) -> Void
    let onStopMonitoring: (String) -> Void
    let onRemove: (String) -> Void
    let onRename: (String, String) -> Void
    let onProjectCleanup: () -> Void
    let onAddProject: () -> Void
    let onRefreshAll: () -> Void
    let onFetchAll: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sidebarControls

            List(selection: selectionBinding) {
                ForEach(groupedProjects, id: \.0) { title, snapshots in
                    groupSection(title: title, snapshots: snapshots)
                }
            }
            .listStyle(.sidebar)
            // Navigation stays neutral while the focused content owns the accent selection.
            .environment(\.controlActiveState, .inactive)
            .scrollContentBackground(.hidden)
            Divider()
                .padding(.horizontal, WorkbenchMetrics.windowPadding)

            sidebarBottomActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Rename Project", isPresented: Binding(
            get: { renameProject != nil },
            set: {
                if !$0 {
                    renameProject = nil
                }
            }
        )) {
            TextField("Project name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameProject = nil }
            Button("Rename") {
                if let project = renameProject {
                    onRename(project.path, renameDraft)
                }
                renameProject = nil
            }
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { normalizedCurrentPath },
            set: { newPath in
                guard let newPath, !newPath.isEmpty, newPath != normalizedCurrentPath else { return }
                onSelect(newPath)
            }
        )
    }

    private var sidebarControls: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Text("Projects")
                .font(.headline)

            Spacer(minLength: 0)

            Button(action: onAddProject) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .frame(minWidth: WorkbenchMetrics.iconHitTarget, minHeight: WorkbenchMetrics.iconHitTarget)
            .help("Add Project")
            .accessibilityLabel("Add Project")
            .accessibilityHint("Choose a local Git repository to monitor.")

            Menu {
                Button(action: onRefreshAll) {
                    Label("Refresh All Projects", systemImage: "arrow.clockwise")
                }
                Button(action: onFetchAll) {
                    Label("Fetch All Projects", systemImage: "arrow.down.circle")
                }
                Divider()
                Button(action: onProjectCleanup) {
                    Label("Project Cleanup…", systemImage: "wand.and.stars")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .frame(minWidth: WorkbenchMetrics.iconHitTarget, minHeight: WorkbenchMetrics.iconHitTarget)
            .help("More Actions")
            .accessibilityLabel("More Project Actions")
        }
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
        .padding(.vertical, WorkbenchMetrics.compactSpacing)
    }

    private var sidebarBottomActions: some View {
        HStack(alignment: .center, spacing: WorkbenchMetrics.compactSpacing) {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
            .contentShape(Rectangle())
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityHint("Open GitMenuBar settings.")

            Spacer(minLength: 0)

            UsageQuotaStripView()
        }
        .frame(minHeight: WorkbenchMetrics.iconHitTarget)
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
        .padding(.vertical, WorkbenchMetrics.microSpacing)
    }

    @ViewBuilder
    private func groupSection(title: String, snapshots: [ProjectStatusSnapshot]) -> some View {
        if title == "Clean" {
            Section(isExpanded: cleanGroupExpanded) {
                projectRows(snapshots)
            } header: {
                groupHeader(title: title, count: snapshots.count)
            }
        } else {
            Section {
                projectRows(snapshots)
            } header: {
                groupHeader(title: title, count: snapshots.count)
            }
        }
    }

    private func projectRows(_ snapshots: [ProjectStatusSnapshot]) -> some View {
        ForEach(snapshots) { snapshot in
            projectRow(snapshot)
                .tag(snapshot.project.path)
        }
    }

    private func groupHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            Text("\(count)")
                .monospacedDigit()
        }
        // Align the count with the row badge column instead of the section's trailing edge.
        .padding(.trailing, WorkbenchMetrics.compactSpacing)
    }

    private func projectRow(_ snapshot: ProjectStatusSnapshot) -> some View {
        ProjectSidebarRowView(
            snapshot: snapshot,
            agentActivities: monitor.agentActivities[snapshot.project.path] ?? [],
            showsAgentActivity: showAgentActivity,
            countColumns: countColumns
        )
        .padding(.vertical, WorkbenchMetrics.headerVerticalPadding)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename Project") {
                renameDraft = snapshot.project.name
                renameProject = snapshot.project
            }
            Button("Reveal in Finder") { onReveal(snapshot.project.path) }
            Button("Stop Monitoring") { onStopMonitoring(snapshot.project.path) }
            Button("Remove Project", role: .destructive) { onRemove(snapshot.project.path) }
        }
    }

    private var cleanGroupExpanded: Binding<Bool> {
        Binding(
            get: { !isCleanGroupCollapsed },
            set: { isCleanGroupCollapsed = !$0 }
        )
    }

    private var normalizedCurrentPath: String {
        RecentProjectsStore.normalize(currentPath)
    }

    private var countColumns: ProjectSidebarCountColumns {
        let visible = groupedProjects.flatMap { title, snapshots in
            title == "Clean" && isCleanGroupCollapsed ? [] : snapshots
        }
        return .guides(for: visible)
    }

    private var groupedProjects: [(String, [ProjectStatusSnapshot])] {
        let values = monitor.monitoredProjects.compactMap { monitor.snapshots[$0.path] }
        let working = showAgentActivity ? values.filter(hasRunningAgent) : []
        let workingPaths = Set(working.map(\.project.path))
        let others = values.filter { !workingPaths.contains($0.project.path) }
        return [
            ("Working", working.sorted(by: projectNameSort)),
            ("Needs Attention", others.filter { $0.classification == .needsAttention }.sorted(by: attentionSort)),
            ("Clean", others.filter { $0.classification == .clean }.sorted(by: projectNameSort)),
            ("Unavailable", others.filter { $0.classification == .unavailable }.sorted(by: projectNameSort))
        ].filter { !$0.1.isEmpty }
    }

    private func hasRunningAgent(_ snapshot: ProjectStatusSnapshot) -> Bool {
        (monitor.agentActivities[snapshot.project.path] ?? []).contains(where: \.status.isRunning)
    }

    private func attentionSort(_ lhs: ProjectStatusSnapshot, _ rhs: ProjectStatusSnapshot) -> Bool {
        if lhs.attentionPriority.sortOrder != rhs.attentionPriority.sortOrder {
            return lhs.attentionPriority.sortOrder < rhs.attentionPriority.sortOrder
        }
        if lhs.isStale != rhs.isStale {
            return lhs.isStale
        }
        if lhs.isStale, lhs.lastActivityAt != rhs.lastActivityAt {
            return (lhs.lastActivityAt ?? .distantPast) < (rhs.lastActivityAt ?? .distantPast)
        }
        return projectNameSort(lhs, rhs)
    }

    private func projectNameSort(_ lhs: ProjectStatusSnapshot, _ rhs: ProjectStatusSnapshot) -> Bool {
        lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending
    }
}

#Preview {
    ProjectsSidebarView(
        currentPath: "",
        onSelect: { _ in },
        onReveal: { _ in },
        onStopMonitoring: { _ in },
        onRemove: { _ in },
        onRename: { _, _ in },
        onProjectCleanup: {},
        onAddProject: {},
        onRefreshAll: {},
        onFetchAll: {},
        onOpenSettings: {}
    )
    .environment(ProjectMonitorStore())
    .environment(UsageQuotaStore())
}
