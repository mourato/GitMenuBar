import SwiftUI

struct ProjectsSidebarView: View {
    @EnvironmentObject private var monitor: ProjectMonitorStore
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
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    UsageQuotaStripView()
                        .padding(.horizontal, WorkbenchMetrics.windowPadding)
                        .padding(.bottom, WorkbenchMetrics.microSpacing)

                    Divider()
                        .padding(.horizontal, WorkbenchMetrics.windowPadding)

                    sidebarBottomActions
                }
            }
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
                .fontWeight(.semibold)

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
        HStack {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .frame(minWidth: WorkbenchMetrics.iconHitTarget, minHeight: WorkbenchMetrics.iconHitTarget)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityHint("Open GitMenuBar settings.")

            Spacer(minLength: 0)
        }
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
    }

    private func projectRow(_ snapshot: ProjectStatusSnapshot) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Circle()
                .fill(snapshot.classification == .clean ? .green : .orange)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 2)
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

    private var groupedProjects: [(String, [ProjectStatusSnapshot])] {
        let values = monitor.monitoredProjects.compactMap { monitor.snapshots[$0.path] }
        return [
            ("Needs Attention", values.filter { $0.classification == .needsAttention }.sorted(by: attentionSort)),
            ("Clean", values.filter { $0.classification == .clean }.sorted(by: projectNameSort)),
            ("Unavailable", values.filter { $0.classification == .unavailable }.sorted(by: projectNameSort))
        ].filter { !$0.1.isEmpty }
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

    private func accessibilityLabel(for snapshot: ProjectStatusSnapshot) -> String {
        var parts = [snapshot.project.name, statusSummary(for: snapshot)]
        if snapshot.hasWorkingTreeChanges {
            parts.append(
                "\(snapshot.stagedCount) staged, \(snapshot.unstagedCount) unstaged, "
                    + "\(snapshot.untrackedCount) untracked"
            )
        }
        if snapshot.unpushedBranchCount > 0 {
            parts.append(
                "\(snapshot.unpushedBranchCount) branch\(snapshot.unpushedBranchCount == 1 ? "" : "es") with unpushed commits"
            )
        }
        if snapshot.unmergedBranchCount > 0 {
            parts.append(
                "\(snapshot.unmergedBranchCount) branch\(snapshot.unmergedBranchCount == 1 ? "" : "es") not merged"
            )
        }
        if let pullRequestSummary = pullRequestSummary(for: snapshot) {
            parts.append(pullRequestSummary)
        }
        if let error = snapshot.lastErrorDescription {
            parts.append(error)
        }
        return parts.joined(separator: ", ")
    }

    private func changeCountSummary(for snapshot: ProjectStatusSnapshot) -> String {
        let count = snapshot.stagedCount + snapshot.unstagedCount + snapshot.untrackedCount
        return count == 1 ? "1 to commit" : "\(count) to commit"
    }

    private func pullRequestSummary(for snapshot: ProjectStatusSnapshot) -> String? {
        if let pullRequest = snapshot.pullRequests.first(where: { $0.headBranch == snapshot.branchName }) {
            return "PR #\(pullRequest.number) \(pullRequest.statusSummary)"
        }
        guard !snapshot.pullRequests.isEmpty else { return nil }
        let count = snapshot.pullRequests.count
        return "\(count) open pull request\(count == 1 ? "" : "s")"
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
                parts.append("\(snapshot.aheadCount) commit\(snapshot.aheadCount == 1 ? "" : "s") to push")
            }
            if snapshot.behindCount > 0 {
                parts.append("\(snapshot.behindCount) commit\(snapshot.behindCount == 1 ? "" : "s") behind")
            }
        }
        if snapshot.unmergedBranchCount > 0 {
            parts.append("\(snapshot.unmergedBranchCount) branch\(snapshot.unmergedBranchCount == 1 ? "" : "es") not merged")
        }
        if let pullRequestSummary = pullRequestSummary(for: snapshot) {
            parts.append(pullRequestSummary)
        }
        if snapshot.isStale {
            parts.append("Stale work")
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
        onFetchAll: {},
        onOpenSettings: {}
    )
    .environmentObject(ProjectMonitorStore())
    .environmentObject(UsageQuotaStore())
}
