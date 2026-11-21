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
                ForEach(groupedProjects, id: \.0) { group, snapshots in
                    groupSection(group, snapshots: snapshots)
                }
            }
            .listStyle(.sidebar)
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
                LucideIconView(name: .plus)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .frame(minWidth: WorkbenchMetrics.iconHitTarget, minHeight: WorkbenchMetrics.iconHitTarget)
            .help("Add Project")
            .accessibilityLabel("Add Project")
            .accessibilityHint("Choose a local Git repository to monitor.")

            Menu {
                Button(action: onRefreshAll) {
                    Label(lucide: .refreshCw, "Refresh All Projects")
                }
                Button(action: onFetchAll) {
                    Label(lucide: .circleArrowDown, "Fetch All Projects")
                }
                Divider()
                Button(action: onProjectCleanup) {
                    Label(lucide: .wandSparkles, "Project Cleanup…")
                }
            } label: {
                LucideIconView(name: .ellipsis)
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
                LucideIconView(name: .settings)
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
    private func groupSection(_ group: ProjectSidebarGroup, snapshots: [ProjectStatusSnapshot]) -> some View {
        if group == .upToDate {
            Section {
                if !isCleanGroupCollapsed {
                    projectRows(snapshots)
                }
            } header: {
                Button {
                    isCleanGroupCollapsed.toggle()
                } label: {
                    HStack(spacing: WorkbenchMetrics.microSpacing) {
                        Text(group.title)
                        Text("\(snapshots.count)")
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        LucideIconView(
                            name: isCleanGroupCollapsed ? .chevronRight : .chevronDown,
                            size: WorkbenchMetrics.sidebarInlineIconSize
                        )
                    }
                    .font(WorkbenchTypography.sectionLabel)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.title), \(snapshots.count == 1 ? "1 project" : "\(snapshots.count) projects")")
                .accessibilityValue(isCleanGroupCollapsed ? "Collapsed" : "Expanded")
            }
        } else {
            Section {
                projectRows(snapshots)
            } header: {
                Text(group.title)
                    .font(WorkbenchTypography.sectionLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func projectRows(_ snapshots: [ProjectStatusSnapshot]) -> some View {
        ForEach(snapshots) { snapshot in
            projectRow(snapshot)
                .tag(snapshot.project.path)
        }
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

    private var normalizedCurrentPath: String {
        RecentProjectsStore.normalize(currentPath)
    }

    private var countColumns: ProjectSidebarCountColumns {
        let visible = groupedProjects.flatMap { group, snapshots in
            group == .upToDate && isCleanGroupCollapsed ? [] : snapshots
        }
        return .guides(for: visible)
    }

    private var groupedProjects: [(ProjectSidebarGroup, [ProjectStatusSnapshot])] {
        let values = monitor.monitoredProjects.compactMap { monitor.snapshots[$0.path] }
        let working = showAgentActivity ? values.filter(hasRunningAgent) : []
        let workingPaths = Set(working.map(\.project.path))
        let others = values.filter { !workingPaths.contains($0.project.path) }
        return ProjectSidebarGroup.allCases.map { group in
            let members = group == .working ? working : others.filter { $0.sidebarGroup == group }
            return (group, members.sorted(by: group == .needsAction || group == .inReview ? attentionSort : projectNameSort))
        }
        .filter { !$0.1.isEmpty }
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
    .environment(UsageQuotaPresentationPreferences())
}
