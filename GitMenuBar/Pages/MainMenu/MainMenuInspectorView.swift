import SwiftUI

struct MainMenuInspectorView: View {
    let projectName: String
    let selection: MainMenuInspectorSelection?
    let overview: RepositoryOverviewSnapshot
    let onClose: () -> Void
    let onManageBranches: () -> Void
    let onRequestDiscard: (String, WorkingTreeFileStatus) -> Void
    let onRequestDeleteBranch: (String) -> Void
    let onRequestSwitchBranch: (String) -> Void

    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @State private var stashPendingDrop: GitStashInfo?
    @State private var isStagedCollapsed = false
    @State private var isUnstagedCollapsed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
                header
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
            .padding(WorkbenchMetrics.panelPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Details")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selection.map { "Details for \($0.title)" } ?? "Details")
        .task(id: selection) {
            await actionCoordinator.prepareInspectorSelection(selection)
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

    private var header: some View {
        HStack(alignment: .top, spacing: WorkbenchMetrics.compactSpacing) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(projectName)
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(selection?.title ?? "Details")
                    .font(WorkbenchTypography.windowTitle)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
            .accessibilityLabel("Close details")
        }
    }

    @ViewBuilder
    private func sectionBody(for selection: MainMenuInspectorSelection) -> some View {
        switch selection {
        case .workingTree:
            workingTreeSection
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
        case .history, .commit:
            historyPlaceholder
        }
    }

    private var workingTreeSection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            if gitManager.stagedFiles.isEmpty, gitManager.changedFiles.isEmpty {
                emptyState("Working tree is clean", systemImage: "checkmark.circle")
            } else {
                if !gitManager.stagedFiles.isEmpty {
                    WorkingTreeSectionView(
                        title: "Staged",
                        summary: gitManager.stagedFiles.sectionSummary,
                        files: gitManager.stagedFiles.map(WorkingTreeRowAdapter.staged(file:)),
                        isCollapsed: $isStagedCollapsed,
                        selectedItemID: nil,
                        onSelect: { _ in },
                        onStageToggle: { path in
                            Task { _ = await actionCoordinator.unstageInspectorFile(path: path) }
                        },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: onRequestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: {
                            Task { _ = await actionCoordinator.unstageAllInspectorFiles() }
                        },
                        onDiscardAll: nil,
                        actionIcon: "minus.circle",
                        actionHelp: "Unstage all files"
                    )
                }
                if !gitManager.changedFiles.isEmpty {
                    WorkingTreeSectionView(
                        title: "Unstaged",
                        summary: gitManager.changedFiles.sectionSummary,
                        files: gitManager.changedFiles.map(WorkingTreeRowAdapter.unstaged(file:)),
                        isCollapsed: $isUnstagedCollapsed,
                        selectedItemID: nil,
                        onSelect: { _ in },
                        onStageToggle: { path in
                            Task { _ = await actionCoordinator.stageInspectorFile(path: path) }
                        },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: onRequestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: {
                            Task { _ = await actionCoordinator.stageAllInspectorFiles() }
                        },
                        onDiscardAll: nil,
                        actionIcon: "plus.circle",
                        actionHelp: "Stage all files"
                    )
                }
            }
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
                HStack {
                    Button("Open") {
                        gitManager.openFile(path: file.path)
                    }
                    if staged {
                        Button("Unstage") {
                            Task { _ = await actionCoordinator.unstageInspectorFile(path: file.path) }
                        }
                    } else {
                        Button("Stage") {
                            Task { _ = await actionCoordinator.stageInspectorFile(path: file.path) }
                        }
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
            emptyState("This file is no longer in the working tree", systemImage: "doc")
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
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            Text("Not merged into the local default branch")
                .font(WorkbenchTypography.sectionLabel)
            Text("These names are local Git reachability against \(gitManager.defaultBranchName.isEmpty ? "the default branch" : gitManager.defaultBranchName), not GitHub pull request status.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            if gitManager.unmergedIntoDefaultBranches.isEmpty {
                Text("None")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(gitManager.unmergedIntoDefaultBranches, id: \.self) { name in
                    branchRow(name: name, unmerged: true)
                }
            }

            Divider()

            Text("Local branches")
                .font(WorkbenchTypography.sectionLabel)
            let localBranches = gitManager.branchInfos.filter(\.isLocal)
            if localBranches.isEmpty {
                emptyState("No local branches", systemImage: "arrow.triangle.branch")
            } else {
                ForEach(localBranches) { info in
                    branchRow(name: info.name, unmerged: gitManager.unmergedIntoDefaultBranches.contains(info.name), tracking: info.trackingStatus, isCurrent: info.isCurrent)
                }
            }

            Button("Manage Branches") {
                onManageBranches()
            }
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
            HStack {
                Button("Switch") {
                    onRequestSwitchBranch(name)
                }
                .disabled(isCurrent || actionCoordinator.isBusy)
                if unmerged, !isCurrent {
                    Button("Merge") {
                        Task { _ = await actionCoordinator.mergeInspectorBranch(name) }
                    }
                    .disabled(actionCoordinator.isBusy)
                }
                Button("Delete", role: .destructive) {
                    onRequestDeleteBranch(name)
                }
                .disabled(isCurrent || actionCoordinator.isBusy)
            }
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
    }

    private var stashesSection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            Text("Retained stash refs")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            if gitManager.stashes.isEmpty {
                emptyState("No retained stashes", systemImage: "archivebox")
            } else {
                ForEach(gitManager.stashes) { stash in
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                        Text(stash.subject.isEmpty ? stash.shortHash : stash.subject)
                            .font(WorkbenchTypography.captionStrong)
                        Text(stashMetadata(stash))
                            .font(WorkbenchTypography.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Apply") {
                                Task { _ = await actionCoordinator.applyInspectorStash(hash: stash.hash) }
                            }
                            .disabled(actionCoordinator.isBusy)
                            Button("Drop", role: .destructive) {
                                stashPendingDrop = stash
                            }
                            .disabled(actionCoordinator.isBusy)
                        }
                    }
                    .padding(WorkbenchMetrics.compactSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(stash.subject)
                    .accessibilityValue(stashMetadata(stash))
                }
            }
        }
    }

    private var historyPlaceholder: some View {
        labeledValue("Loaded commits", "\(overview.historyCount)")
            .padding(WorkbenchMetrics.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
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

    private func emptyState(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
    }

    private func metricLabel(_ metric: RepositoryMetricState<Int>, unit: String) -> String {
        switch metric {
        case let .known(count):
            "\(count) \(unit)\(count == 1 ? "" : "s")"
        case .loading:
            "Checking"
        case .unavailable:
            "Not checked yet"
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

#Preview("No Selection") {
    MainMenuPreviewHarness {
        MainMenuInspectorView(
            projectName: "GitMenuBar",
            selection: nil,
            overview: .empty,
            onClose: {},
            onManageBranches: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

#Preview("Working Tree") {
    MainMenuPreviewHarness {
        MainMenuInspectorView(
            projectName: "GitMenuBar",
            selection: .workingTree,
            overview: .empty,
            onClose: {},
            onManageBranches: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 420)
}

#Preview("Stashes") {
    MainMenuPreviewHarness {
        MainMenuInspectorView(
            projectName: "GitMenuBar",
            selection: .stashes,
            overview: .empty,
            onClose: {},
            onManageBranches: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}
