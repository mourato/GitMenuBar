import SwiftUI

/// Inspector detail surface for selections that are neither the commit
/// workspace nor history. The parent routes `.workingTree` and
/// `.history`/`.commit` elsewhere, so this view only handles detail cases.
struct InspectorDetailView: View {
    let projectName: String
    let selection: MainMenuInspectorSelection?
    let overview: RepositoryOverviewSnapshot
    let onManageBranches: () -> Void
    let onRequestDiscard: (String, WorkingTreeFileStatus) -> Void
    let onRequestDeleteBranch: (String) -> Void
    let onRequestSwitchBranch: (String) -> Void

    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @State private var stashPendingDrop: GitStashInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            InspectorHeaderView(projectName: projectName, title: selection?.title ?? "Details")
            ScrollView {
                if let selection {
                    sectionBody(for: selection)
                } else {
                    ContentUnavailableView(
                        "No details selected",
                        systemImage: "sidebar.right",
                        description: Text("Select an item in the workbench to view its details.")
                    )
                }
            }
        }
        .alert(
            "Drop stash?",
            isPresented: Binding(
                get: { stashPendingDrop != nil },
                set: { isPresented in
                    if !isPresented {
                        stashPendingDrop = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                stashPendingDrop = nil
            }
            Button("Drop", role: .destructive) {
                if let stashPendingDrop {
                    Task {
                        _ = await actionCoordinator.dropInspectorStash(hash: stashPendingDrop.hash)
                    }
                }
                stashPendingDrop = nil
            }
        } message: {
            Text("This removes the retained stash from the repository. Git cannot undo that drop.")
        }
    }

    @ViewBuilder
    private func sectionBody(for selection: MainMenuInspectorSelection) -> some View {
        switch selection {
        case let .stagedFile(path):
            fileDetail(path: path, staged: true)
        case let .unstagedFile(path):
            fileDetail(path: path, staged: false)
        case .unpushedCommits:
            pushSyncSection
        case .branches, .branch:
            branchesSection
        case .stashes, .stash:
            stashesSection
        case .workingTree, .history, .commit:
            // Routed to a dedicated surface by the parent; no content here.
            EmptyView()
        }
    }

    @ViewBuilder
    private func fileDetail(path: String, staged: Bool) -> some View {
        let files = staged ? gitManager.stagedFiles : gitManager.changedFiles
        if let file = files.first(where: { $0.path == path }) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                labeledValue("Path", file.path)
                labeledValue("Status", file.status.rawValue.capitalized)
                labeledValue("Lines", "+\(file.lineDiff.added) −\(file.lineDiff.removed)")
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    Button("Open") {
                        gitManager.openFile(path: file.path)
                    }
                    .workbenchGhost()
                    if staged {
                        Button("Unstage") {
                            Task { _ = await actionCoordinator.unstageInspectorFile(path: file.path) }
                        }
                        .workbenchGhost()
                    } else {
                        Button("Stage") {
                            Task { _ = await actionCoordinator.stageInspectorFile(path: file.path) }
                        }
                        .workbenchGhost()
                        if file.status != .untracked {
                            Button("Discard", role: .destructive) {
                                onRequestDiscard(file.path, file.status)
                            }
                        }
                    }
                }
            }
            .padding(WorkbenchMetrics.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
        } else {
            emptyState("This file is no longer in the working tree", systemImage: "doc", description: "It was staged, discarded, or the working tree refreshed.")
        }
    }

    private var pushSyncSection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            labeledValue("Current branch", gitManager.isDetachedHead ? "Detached HEAD" : gitManager.currentBranch)
            labeledValue("Ahead", metricLabel(overview.aheadCount, unit: "commit"))
            labeledValue("Behind", metricLabel(overview.behindCount, unit: "commit"))
            if gitManager.remoteUrl.isEmpty {
                Text("No remote is configured, so Push is unavailable.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Push") {
                Task {
                    _ = await actionCoordinator.pushInspectorBranch(gitManager.currentBranch)
                }
            }
            .workbenchSecondary()
            .disabled(
                actionCoordinator.isBusy
                    || gitManager.remoteUrl.isEmpty
                    || gitManager.isDetachedHead
                    || gitManager.currentBranch.isEmpty
            )
            .accessibilityHint("Pushes the current local branch to origin without force")
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
    }

    private var branchesSection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            Text("Not merged into the local default branch")
                .font(WorkbenchTypography.sectionLabel)
            Text("These names are local Git reachability against \(gitManager.defaultBranchName.isEmpty ? "the default branch" : gitManager.defaultBranchName), not GitHub pull request status.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            if gitManager.unmergedIntoDefaultBranches.isEmpty {
                Text("None — everything is merged")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(gitManager.unmergedIntoDefaultBranches, id: \.self) { name in
                    branchRow(name: name, unmerged: true)
                }
            }

            Text("Local branches")
                .font(WorkbenchTypography.sectionLabel)
            let localBranches = gitManager.branchInfos.filter(\.isLocal)
            if localBranches.isEmpty {
                emptyState("No local branches", systemImage: "arrow.triangle.branch", description: "Create a branch to start isolated work.")
            } else {
                ForEach(localBranches) { info in
                    branchRow(name: info.name, unmerged: gitManager.unmergedIntoDefaultBranches.contains(info.name), tracking: info.trackingStatus, isCurrent: info.isCurrent)
                }
            }

            Button("Manage Branches") {
                onManageBranches()
            }
            .workbenchGhost()
        }
    }

    private func branchRow(
        name: String,
        unmerged: Bool,
        tracking: BranchTrackingStatus? = nil,
        isCurrent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            HStack {
                Text(name)
                    .font(WorkbenchTypography.captionStrong)
                    .lineLimit(1)
                if isCurrent {
                    Text("Current")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let tracking {
                Text(tracking.description)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Button("Switch") {
                    onRequestSwitchBranch(name)
                }
                .workbenchGhost()
                .disabled(isCurrent || actionCoordinator.isBusy)
                if unmerged, !isCurrent {
                    Button("Merge") {
                        Task { _ = await actionCoordinator.mergeInspectorBranch(name) }
                    }
                    .workbenchGhost()
                    .disabled(actionCoordinator.isBusy)
                }
                Button("Delete", role: .destructive) {
                    onRequestDeleteBranch(name)
                }
                .disabled(isCurrent || actionCoordinator.isBusy)
            }
        }
        .padding(WorkbenchMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name)\(isCurrent ? ", current branch" : "")")
    }

    private var stashesSection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            Text("Retained stash refs")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            if gitManager.stashes.isEmpty {
                emptyState("No retained stashes", systemImage: "archivebox", description: "Stash to park work in progress without committing.")
            } else {
                ForEach(gitManager.stashes) { stash in
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                        Text(stash.subject.isEmpty ? stash.shortHash : stash.subject)
                            .font(WorkbenchTypography.captionStrong)
                            .lineLimit(2)
                        Text(stashMetadata(stash))
                            .font(WorkbenchTypography.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        HStack(spacing: WorkbenchMetrics.compactSpacing) {
                            Button("Apply") {
                                Task { _ = await actionCoordinator.applyInspectorStash(hash: stash.hash) }
                            }
                            .workbenchGhost()
                            .disabled(actionCoordinator.isBusy)
                            Button("Drop", role: .destructive) {
                                stashPendingDrop = stash
                            }
                            .disabled(actionCoordinator.isBusy)
                        }
                    }
                    .padding(WorkbenchMetrics.sectionSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(stash.subject.isEmpty ? "Stash \(stash.shortHash)" : stash.subject)
                    .accessibilityValue(stashMetadata(stash))
                }
            }
        }
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Text(title)
                .font(WorkbenchTypography.sectionLabel)
            Text(value)
                .font(WorkbenchTypography.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func emptyState(_ title: String, systemImage: String, description: String? = nil) -> some View {
        if let description {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        } else {
            ContentUnavailableView(title, systemImage: systemImage)
        }
    }

    private func metricLabel(_ metric: RepositoryMetricState<Int>, unit: String) -> String {
        switch metric {
        case let .known(count):
            "\(count) \(unit)\(count == 1 ? "" : "s")"
        case .loading:
            "Checking…"
        case .unavailable:
            "Not available"
        }
    }

    private func stashMetadata(_ stash: GitStashInfo) -> String {
        var parts = [stash.shortHash]
        if let branchName = stash.branchName {
            parts.append(branchName)
        }
        if let createdAt = stash.createdAt {
            parts.append(createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }
}
