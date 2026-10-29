import SwiftUI

struct ProjectsSidebarView: View {
    @Environment(ProjectMonitorStore.self) private var monitor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
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
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
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
    }

    private func projectRow(_ snapshot: ProjectStatusSnapshot) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Circle()
                .fill(dotColor(for: snapshot))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.project.name)
                    .lineLimit(1)
                Text(statusSummary(for: snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            HStack(spacing: WorkbenchMetrics.microSpacing) {
                if showAgentActivity, !(monitor.agentActivities[snapshot.project.path] ?? []).isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: WorkbenchMetrics.microSpacing) {
                            ForEach(monitor.agentActivities[snapshot.project.path] ?? []) { activity in
                                AgentBadgeIconView(activity: activity)
                            }
                        }
                        .fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                }

                if snapshot.hasWorkingTreeChanges {
                    changeCountBadge(for: snapshot)
                }
            }
        }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: snapshot))
    }

    private func dotColor(for snapshot: ProjectStatusSnapshot) -> Color {
        guard snapshot.classification != .clean else {
            return .green
        }
        switch snapshot.severity {
        case .divergedOrBehind:
            return .red
        case .uncommittedChanges:
            return .orange
        case .unmergedOnly, .none:
            return .secondary
        }
    }

    private func changeCountBadge(for snapshot: ProjectStatusSnapshot) -> some View {
        let count = snapshot.stagedCount + snapshot.unstagedCount + snapshot.untrackedCount
        return Text("\(count)")
            .font(WorkbenchTypography.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, WorkbenchMetrics.chipSpacing)
            .padding(.vertical, WorkbenchMetrics.headerVerticalPadding)
            .background(
                Capsule()
                    .fill(WorkbenchPalette.hoverFill())
            )
            .overlay(
                Capsule()
                    .strokeBorder(WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast), lineWidth: 1)
            )
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

    private func accessibilityLabel(for snapshot: ProjectStatusSnapshot) -> String {
        var parts = [snapshot.project.name, statusSummary(for: snapshot)]
        if showAgentActivity, !(monitor.agentActivities[snapshot.project.path] ?? []).isEmpty {
            let agentDescriptions = (monitor.agentActivities[snapshot.project.path] ?? []).map(\.accessibilityDescription).joined(separator: ", ")
            parts.append(agentDescriptions)
        }
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

    private func pullRequestSummary(for snapshot: ProjectStatusSnapshot) -> String? {
        if let pullRequest = snapshot.pullRequests.first(where: { $0.headBranch == snapshot.branchName }) {
            return "PR #\(pullRequest.number) \(pullRequest.statusSummary)"
        }
        guard !snapshot.pullRequests.isEmpty else { return nil }
        let count = snapshot.pullRequests.count
        return "\(count) open pull request\(count == 1 ? "" : "s")"
    }

    private func branchSummary(for snapshot: ProjectStatusSnapshot) -> String? {
        if snapshot.isDetachedHead {
            return "Detached"
        }
        if snapshot.branchName.isEmpty {
            return "Unknown branch"
        }
        return snapshot.isDefaultBranch ? nil : snapshot.branchName
    }

    private func upstreamSummary(for snapshot: ProjectStatusSnapshot) -> [String] {
        guard snapshot.hasUpstream else { return [] }
        var parts: [String] = []
        if snapshot.aheadCount > 0 {
            parts.append("\(snapshot.aheadCount) commit\(snapshot.aheadCount == 1 ? "" : "s") to push")
        }
        if snapshot.behindCount > 0 {
            parts.append("\(snapshot.behindCount) commit\(snapshot.behindCount == 1 ? "" : "s") behind")
        }
        return parts
    }

    private func statusSummary(for snapshot: ProjectStatusSnapshot) -> String {
        if snapshot.lastErrorDescription != nil {
            return "Unavailable"
        }

        var parts: [String] = []
        if let branch = branchSummary(for: snapshot) {
            parts.append(branch)
        }
        parts.append(contentsOf: upstreamSummary(for: snapshot))
        if snapshot.unmergedBranchCount > 0 {
            parts.append("\(snapshot.unmergedBranchCount) branch\(snapshot.unmergedBranchCount == 1 ? "" : "es") not merged")
        }
        if let pullRequestSummary = pullRequestSummary(for: snapshot) {
            parts.append(pullRequestSummary)
        }
        if snapshot.isStale {
            parts.append("Stale work")
        }
        if parts.isEmpty {
            return snapshot.hasWorkingTreeChanges ? "Uncommitted changes" : "Up to date"
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
    .environment(ProjectMonitorStore())
    .environment(UsageQuotaStore())
}
