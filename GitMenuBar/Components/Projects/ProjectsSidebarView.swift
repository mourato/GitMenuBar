import SwiftUI

struct ProjectsSidebarView: View {
    @EnvironmentObject private var monitor: ProjectMonitorStore
    @AppStorage(AppPreferences.Keys.isCleanProjectsGroupCollapsed) private var isCleanGroupCollapsed = false
    @State private var renameProject: ProjectReference?
    @State private var renameDraft = ""
    @State private var selection: String?

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

    var body: some View {
        VStack(spacing: 0) {
            sidebarControls

            List(selection: $selection) {
                ForEach(groupedProjects, id: \.0) { title, snapshots in
                    groupSection(title: title, snapshots: snapshots)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                UsageQuotaStripView()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: synchronizeSelection)
        .onChange(of: currentPath) { _ in
            synchronizeSelection()
        }
        .onChange(of: selection) { path in
            guard let path, path != normalizedCurrentPath else { return }
            Task { @MainActor in
                await Task.yield()
                guard selection == path, path != normalizedCurrentPath else { return }
                onSelect(path)
            }
        }
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

    private var sidebarControls: some View {
        HStack(spacing: 4) {
            Text("Projects")
                .font(.headline)

            Spacer(minLength: 0)

            sidebarButton(
                systemImage: "wand.and.stars",
                accessibilityLabel: "Project Cleanup",
                accessibilityHint: "Review safe branch and worktree cleanup across monitored projects.",
                action: onProjectCleanup
            )
            sidebarButton(
                systemImage: "plus",
                accessibilityLabel: "Add Project",
                accessibilityHint: "Choose a local Git repository to monitor.",
                action: onAddProject
            )
            sidebarButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: "Refresh All Projects",
                accessibilityHint: "Refreshes the Git status for every monitored project.",
                action: onRefreshAll
            )
            sidebarButton(
                systemImage: "arrow.down.circle",
                accessibilityLabel: "Fetch All Projects",
                accessibilityHint: "Fetches remotes for every monitored project.",
                action: onFetchAll
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func sidebarButton(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .frame(minWidth: WorkbenchMetrics.iconHitTarget, minHeight: WorkbenchMetrics.iconHitTarget)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
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
                .tag(snapshot.project.path as String?)
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
    }

    private func projectRow(_ snapshot: ProjectStatusSnapshot) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(snapshot.classification == .clean ? .green : .orange)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.project.name)
                    .lineLimit(1)
                Text(statusSummary(for: snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if snapshot.hasWorkingTreeChanges {
                Text(changeCountSummary(for: snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: snapshot))
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

    private func synchronizeSelection() {
        selection = normalizedCurrentPath.isEmpty ? nil : normalizedCurrentPath
    }

    private var groupedProjects: [(String, [ProjectStatusSnapshot])] {
        let values = monitor.monitoredProjects.compactMap { monitor.snapshots[$0.path] }
        return [
            ("Needs Attention", values.filter { $0.classification == .needsAttention }),
            ("Clean", values.filter { $0.classification == .clean }),
            ("Unavailable", values.filter { $0.classification == .unavailable })
        ].filter { !$0.1.isEmpty }
    }

    private func accessibilityLabel(for snapshot: ProjectStatusSnapshot) -> String {
        var parts = [snapshot.project.name, statusSummary(for: snapshot)]
        if snapshot.hasWorkingTreeChanges {
            parts.append(
                "\(snapshot.stagedCount) staged, \(snapshot.unstagedCount) unstaged, "
                    + "\(snapshot.untrackedCount) untracked"
            )
        }
        if let error = snapshot.lastErrorDescription {
            parts.append(error)
        }
        return parts.joined(separator: ", ")
    }

    private func changeCountSummary(for snapshot: ProjectStatusSnapshot) -> String {
        let count = snapshot.stagedCount + snapshot.unstagedCount + snapshot.untrackedCount
        return count == 1 ? "1 changed" : "\(count) changed"
    }

    private func statusSummary(for snapshot: ProjectStatusSnapshot) -> String {
        if snapshot.lastErrorDescription != nil {
            return "Unavailable"
        }

        let branch = if snapshot.isDetachedHead {
            "Detached"
        } else if snapshot.branchName.isEmpty {
            "Unknown branch"
        } else {
            snapshot.branchName
        }
        var parts = [branch]
        if snapshot.hasUpstream {
            if snapshot.aheadCount > 0 {
                parts.append("↑\(snapshot.aheadCount)")
            }
            if snapshot.behindCount > 0 {
                parts.append("↓\(snapshot.behindCount)")
            }
        } else {
            parts.append("No upstream")
        }
        return parts.joined(separator: " ")
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
        onFetchAll: {}
    )
    .environmentObject(ProjectMonitorStore())
    .environmentObject(UsageQuotaStore())
}
