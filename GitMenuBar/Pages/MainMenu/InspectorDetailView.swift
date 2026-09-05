import SwiftUI

/// Inspector detail surface for selections that are neither the commit
/// workspace nor history. The parent routes `.workingTree` and
/// `.history`/`.commit` elsewhere, so this view only handles detail cases.
struct InspectorDetailView: View {
    let projectName: String
    let selection: MainMenuInspectorSelection?
    let overview: RepositoryOverviewSnapshot
    let onRequestDiscard: (String, WorkingTreeFileStatus) -> Void
    let onRequestDeleteBranch: (String) -> Void
    let onRequestSwitchBranch: (String) -> Void
    let onCreateBranch: () -> Void
    let onRenameBranch: (String) -> Void

    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @State private var stashPendingDrop: GitStashInfo?

    init(
        projectName: String,
        selection: MainMenuInspectorSelection?,
        overview: RepositoryOverviewSnapshot,
        onRequestDiscard: @escaping (String, WorkingTreeFileStatus) -> Void,
        onRequestDeleteBranch: @escaping (String) -> Void,
        onRequestSwitchBranch: @escaping (String) -> Void,
        onCreateBranch: @escaping () -> Void = {},
        onRenameBranch: @escaping (String) -> Void = { _ in }
    ) {
        self.projectName = projectName
        self.selection = selection
        self.overview = overview
        self.onRequestDiscard = onRequestDiscard
        self.onRequestDeleteBranch = onRequestDeleteBranch
        self.onRequestSwitchBranch = onRequestSwitchBranch
        self.onCreateBranch = onCreateBranch
        self.onRenameBranch = onRenameBranch
    }

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
            Text(pushSyncGuidance)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Button(pushSyncPrimaryTitle) {
                    Task {
                        if isCurrentBranchUnpublished {
                            _ = await actionCoordinator.publishInspectorBranch(gitManager.currentBranch)
                        } else {
                            _ = await actionCoordinator.pushInspectorBranch(gitManager.currentBranch)
                        }
                    }
                }
                .workbenchSecondary()
                .disabled(
                    actionCoordinator.isBusy
                        || gitManager.remoteUrl.isEmpty
                        || gitManager.isDetachedHead
                        || gitManager.currentBranch.isEmpty
                        || pushSyncAhead == 0
                )
                .accessibilityHint("Pushes the current local branch to origin without force")
                Menu("Pull") {
                    Button("Pull") {
                        Task { _ = await actionCoordinator.pullInspectorBranch(rebase: false) }
                    }
                    .disabled(!canPull)
                    Button("Pull with Rebase") {
                        Task { _ = await actionCoordinator.pullInspectorBranch(rebase: true) }
                    }
                    .disabled(!canPull)
                }
                .workbenchGhost()
                .disabled(!canPull)
                .accessibilityHint("Fetches and integrates remote changes into the current branch")
            }
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
    }

    private var pushSyncAhead: Int {
        if case let .known(count) = overview.aheadCount {
            count
        } else {
            0
        }
    }

    private var pushSyncBehind: Int {
        if case let .known(count) = overview.behindCount {
            count
        } else {
            0
        }
    }

    private var isCurrentBranchUnpublished: Bool {
        gitManager.branchInfos.first(where: \.isCurrent)?.trackingStatus == .noRemote
    }

    private var canPull: Bool {
        !actionCoordinator.isBusy
            && !gitManager.remoteUrl.isEmpty
            && !gitManager.isDetachedHead
            && !gitManager.currentBranch.isEmpty
            && pushSyncBehind > 0
    }

    private var pushSyncPrimaryTitle: String {
        isCurrentBranchUnpublished ? "Publish" : "Push"
    }

    private var pushSyncGuidance: String {
        if gitManager.isDetachedHead {
            return "Detached HEAD — create a branch to push."
        }
        if gitManager.remoteUrl.isEmpty {
            return "No remote is configured, so Push is unavailable."
        }
        if pushSyncAhead > 0, pushSyncBehind > 0 {
            return "Diverged — pull first, then push."
        }
        if pushSyncBehind > 0 {
            return "Behind — pull to get up to date."
        }
        if pushSyncAhead > 0 {
            return isCurrentBranchUnpublished
                ? "No upstream — publish to get clean."
                : "Ahead — push to get clean."
        }
        return "Up to date."
    }

    private var branchesSection: some View {
        InspectorBranchManagementView(
            onRequestDeleteBranch: onRequestDeleteBranch,
            onRequestSwitchBranch: onRequestSwitchBranch,
            onCreateBranch: onCreateBranch,
            onRenameBranch: onRenameBranch
        )
    }

    private var stashesSection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            HStack {
                Text("Retained stash refs")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Stash changes") {
                    Task { _ = await actionCoordinator.saveInspectorStash() }
                }
                .workbenchGhost()
                .disabled(actionCoordinator.isBusy || !hasWorkingTreeChanges)
                .accessibilityHint("Parks working tree changes in a new stash")
            }
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
                            Menu("Apply") {
                                Button("Apply") {
                                    Task { _ = await actionCoordinator.applyInspectorStash(hash: stash.hash) }
                                }
                                .disabled(actionCoordinator.isBusy)
                                Button("Apply and drop") {
                                    Task { _ = await actionCoordinator.popInspectorStash(hash: stash.hash) }
                                }
                                .disabled(actionCoordinator.isBusy)
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

    private var hasWorkingTreeChanges: Bool {
        !gitManager.stagedFiles.isEmpty || !gitManager.changedFiles.isEmpty
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
