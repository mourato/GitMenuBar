import AppKit
import SwiftUI

/// Branch Health management surface hosted by the inspector. It covers the
/// Branches, Worktrees, and Cleanup modes previously owned by the
/// BranchManagementSheet, reusing its row and content views.
struct SidePanelBranchManagementView: View {
    let onRequestDeleteBranch: (String) -> Void
    let onRequestSwitchBranch: (String) -> Void
    let onCreateBranch: () -> Void
    let onRenameBranch: (String) -> Void

    @Environment(GitManager.self) private var gitManager
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var branchQuery = ""
    @State private var filter: BranchFilter = .all
    @State private var branchesExpanded = true
    @State private var worktreesExpanded = false
    @State private var moreMergedExpanded = false
    @State private var deleteRemoteBranch: BranchInfo?
    @State private var pendingReadyUnits: [GitCleanupUnit] = []
    @State private var pendingBlockedUnits: [GitCleanupUnit] = []
    @State private var showCleanupConfirmation = false

    private var defaultBranchDisplayName: String {
        gitManager.defaultBranchName.isEmpty ? "the default branch" : gitManager.defaultBranchName
    }

    private var listModel: BranchListModel {
        BranchListResolver.resolve(
            branches: gitManager.branchInfos,
            snapshot: gitManager.worktreeSnapshot,
            query: branchQuery,
            filter: filter,
            now: Date()
        )
    }

    var body: some View {
        let model = listModel
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            branchesGroup(model: model)
        }
        .alert("Delete Remote Branch?", isPresented: Binding(
            get: { deleteRemoteBranch != nil },
            set: {
                if !$0 {
                    deleteRemoteBranch = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                guard let branch = deleteRemoteBranch else { return }
                deleteRemoteBranch = nil
                Task {
                    _ = await actionCoordinator.sidePanel.deleteRemoteSidePanelBranch(
                        branch.name,
                        remoteName: branch.remoteName ?? "origin"
                    )
                }
            }
            Button("Cancel", role: .cancel) { deleteRemoteBranch = nil }
        } message: {
            if let branch = deleteRemoteBranch {
                Text("This will permanently delete '\(branch.displayName)' on the remote. This cannot be undone.")
            }
        }
        .sheet(isPresented: $showCleanupConfirmation) {
            CleanupConfirmationView(
                units: pendingReadyUnits,
                blocked: pendingBlockedUnits,
                onCancel: dismissCleanupConfirmation,
                onConfirm: { unitsToClean in
                    runCleanup(units: unitsToClean)
                }
            )
        }
    }

    private func branchesGroup(model: BranchListModel) -> some View {
        DisclosureGroup(isExpanded: $branchesExpanded) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                headerCaption

                filterField(query: $branchQuery, placeholder: "Filter branches")

                filterChipsRow(model: model)

                if let progress = gitManager.cleanupProgress {
                    CleanupProgressView(progress: progress)
                }

                if model.readyCount > 0 {
                    cleanupBanner(model: model)
                }

                if let current = model.current {
                    pinnedCurrentBranchRow(current, model: model)
                }

                localSection(model: model)

                remoteSection(model: model)

                if isListEmpty(model: model) {
                    Text("No branches match your filter.")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }

                footer

                if worktreesExpanded {
                    worktreesContent
                }
            }
            .adaptiveMotion()
        } label: {
            Text("Branches (\(gitManager.branchInfos.filter(\.isLocal).count))")
                .font(WorkbenchTypography.sectionLabel)
        }
    }

    private var headerCaption: some View {
        Text("vs \(defaultBranchDisplayName) · local")
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
            .help("Local Git reachability against \(defaultBranchDisplayName), not GitHub pull request status.")
    }

    private func filterChipsRow(model: BranchListModel) -> some View {
        HStack(spacing: WorkbenchMetrics.chipSpacing) {
            ForEach(BranchFilter.allCases, id: \.self) { item in
                let count = model.count(for: item)
                let isSelected = filter == item
                Button {
                    withAnimation(WorkbenchMotion.swap) {
                        filter = item
                    }
                } label: {
                    HStack(spacing: WorkbenchMetrics.microSpacing) {
                        Text(item.title)
                        Text("\(count)")
                            .monospacedDigit()
                            .opacity(isSelected ? 0.9 : 0.6)
                    }
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : WorkbenchPalette.hoverFill())
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title), \(count) \(count == 1 ? "branch" : "branches")")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func cleanupBanner(model: BranchListModel) -> some View {
        HStack(alignment: .center, spacing: WorkbenchMetrics.compactSpacing) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text("\(model.readyCount) ready to clean")
                    .font(WorkbenchTypography.sectionLabel)
                Text("\(model.blockedCount) blocked · merged or cherry-picked")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: WorkbenchMetrics.compactSpacing)
            Button("Review…") {
                guard let snapshot = gitManager.worktreeSnapshot else { return }
                let matching = snapshot.managementUnits(matching: branchQuery)
                let ready = matching.filter(\.canPrimaryClean)
                let blocked = matching.filter { !$0.canPrimaryClean }
                presentCleanupConfirmation(ready: ready, blocked: blocked)
            }
            .workbenchSecondary()
            .disabled(actionCoordinator.isBusy)
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.compactSpacing)
        .background(
            WorkbenchPalette.successFill(contrast: colorSchemeContrast),
            in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
        )
    }

    private func pinnedCurrentBranchRow(_ current: BranchInfo, model: BranchListModel) -> some View {
        let currentStatus = model.local.first(where: \.branch.isCurrent)?.cleanupStatus
        return localManagementRow(current, cleanupStatus: mapCleanupStatus(currentStatus))
            .background(
                WorkbenchPalette.accentFill(contrast: colorSchemeContrast),
                in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
            )
            .transition(.opacity)
    }

    @ViewBuilder
    private func localSection(model: BranchListModel) -> some View {
        let nonCurrentVisible = model.visible.filter { !$0.branch.isCurrent }
        let totalCount = nonCurrentVisible.count + model.collapsedMerged.count

        if totalCount > 0 {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                Text("LOCAL · \(totalCount)")
                    .font(WorkbenchTypography.captionStrong)
                    .textCase(.uppercase)
                    .tracking(WorkbenchTypography.tracking(for: WorkbenchTypography.caption))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    ForEach(nonCurrentVisible) { row in
                        localManagementRow(row.branch, cleanupStatus: mapCleanupStatus(row.cleanupStatus))
                            .transition(.opacity)
                    }
                }

                if model.hasCollapsedMerged {
                    DisclosureGroup(
                        isExpanded: $moreMergedExpanded,
                        content: {
                            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                                ForEach(model.collapsedMerged) { row in
                                    localManagementRow(row.branch, cleanupStatus: mapCleanupStatus(row.cleanupStatus))
                                        .transition(.opacity)
                                }
                            }
                        },
                        label: {
                            Text("\(model.collapsedMerged.count) more merged branches")
                                .font(WorkbenchTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func remoteSection(model: BranchListModel) -> some View {
        let remoteTotalCount = model.remoteGroups.reduce(0) { $0 + $1.branches.count } + model.ungroupedRemote.count

        if remoteTotalCount > 0 {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                Text("REMOTE · \(remoteTotalCount)")
                    .font(WorkbenchTypography.captionStrong)
                    .textCase(.uppercase)
                    .tracking(WorkbenchTypography.tracking(for: WorkbenchTypography.caption))
                    .foregroundStyle(.secondary)

                ForEach(model.remoteGroups) { group in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                            ForEach(group.branches) { branch in
                                remoteManagementRow(branch)
                                    .transition(.opacity)
                            }
                        }
                    } label: {
                        HStack(spacing: WorkbenchMetrics.compactSpacing) {
                            Text(group.name)
                                .font(WorkbenchTypography.body)
                                .foregroundStyle(.primary)
                            Text("\(group.branches.count)")
                                .font(WorkbenchTypography.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, WorkbenchMetrics.chipSpacing)
                                .padding(.vertical, WorkbenchMetrics.microSpacing / 2)
                                .background(
                                    Capsule()
                                        .fill(WorkbenchPalette.hoverFill())
                                )
                        }
                    }
                }

                ForEach(model.ungroupedRemote) { branch in
                    remoteManagementRow(branch)
                        .transition(.opacity)
                }
            }
        }
    }

    private var footer: some View {
        let worktreeCount = gitManager.worktreeSnapshot?.worktrees.count ?? 0
        return HStack {
            Button {
                onCreateBranch()
            } label: {
                Label("New Branch", systemImage: "plus")
            }
            .workbenchSecondary()
            .disabled(actionCoordinator.isBusy)

            Spacer()

            Button {
                withAnimation(WorkbenchMotion.swap) {
                    worktreesExpanded.toggle()
                }
            } label: {
                Text("Worktrees \(worktreeCount) \(worktreesExpanded ? "▾" : "▸")")
            }
            .workbenchGhost()
            .disabled(actionCoordinator.isBusy)
            .accessibilityLabel("Worktrees, \(worktreeCount)")
        }
    }

    @ViewBuilder
    private var worktreesContent: some View {
        if let snapshot = gitManager.worktreeSnapshot {
            WorktreeManagementContentView(
                snapshot: snapshot,
                errorMessage: nil,
                query: branchQuery,
                onReveal: revealWorktree,
                onCopyPath: copyPath,
                onForceRemove: forceRemoveWorktree,
                onDismissError: {}
            )
            .transition(.opacity)
        } else {
            Text("No cleanup analysis is available.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func localManagementRow(_ info: BranchInfo, cleanupStatus: GitBranchCleanupStatus? = nil) -> some View {
        BranchManagementRowView(
            branch: info,
            onSwitch: { onRequestSwitchBranch(info.displayName) },
            onRename: { onRenameBranch(info.name) },
            onDelete: { onRequestDeleteBranch(info.name) },
            onPush: needsPush(info) ? {
                Task {
                    if info.trackingStatus == .noRemote {
                        _ = await actionCoordinator.sidePanel.publishSidePanelBranch(info.name)
                    } else {
                        _ = await actionCoordinator.sidePanel.pushSidePanelBranch(info.name)
                    }
                }
            } : nil,
            onMerge: gitManager.unmergedIntoDefaultBranches.contains(info.name) && !info.isCurrent ? {
                Task { _ = await actionCoordinator.sidePanel.mergeSidePanelBranch(info.name) }
            } : nil,
            onDeleteRemote: nil,
            onCheckoutLocally: nil,
            cleanupStatus: cleanupStatus
        )
        .disabled(actionCoordinator.isBusy)
    }

    private func remoteManagementRow(_ info: BranchInfo) -> some View {
        BranchManagementRowView(
            branch: info,
            onSwitch: {},
            onRename: {},
            onDelete: {},
            onPush: nil,
            onMerge: nil,
            onDeleteRemote: { deleteRemoteBranch = info },
            onCheckoutLocally: {
                Task {
                    _ = await actionCoordinator.sidePanel.checkoutRemoteSidePanelBranch(
                        info.name,
                        remoteName: info.remoteName ?? "origin"
                    )
                }
            },
            cleanupStatus: nil
        )
        .disabled(actionCoordinator.isBusy)
    }

    private func mapCleanupStatus(_ status: BranchCleanupBadgeStatus?) -> GitBranchCleanupStatus? {
        switch status {
        case .merged:
            .mergedIntoDefault
        case .dirty:
            .notMerged
        case .blocked, .none:
            nil
        }
    }

    private func filterField(query: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: query)
                .textFieldStyle(.plain)
                .font(WorkbenchTypography.body)
            if !query.wrappedValue.isEmpty {
                Button {
                    query.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .accessibilityLabel(placeholder)
    }

    private func isListEmpty(model: BranchListModel) -> Bool {
        model.current == nil && model.local.isEmpty && model.remoteGroups.isEmpty && model.ungroupedRemote.isEmpty
    }

    private func needsPush(_ info: BranchInfo) -> Bool {
        switch info.trackingStatus {
        case .noRemote, .ahead, .diverged:
            true
        case .upToDate, .behind, .unknown:
            false
        }
    }

    private func presentCleanupConfirmation(ready: [GitCleanupUnit], blocked: [GitCleanupUnit] = []) {
        guard !ready.isEmpty || !blocked.isEmpty else { return }
        pendingReadyUnits = ready
        pendingBlockedUnits = blocked
        showCleanupConfirmation = true
    }

    private func forceRemoveWorktree(_ info: GitWorktreeCleanupInfo) {
        guard let snapshot = gitManager.worktreeSnapshot, snapshot.canForceRemove(info) else { return }
        presentCleanupConfirmation(
            ready: [GitCleanupUnit.forceWorktreeRemoval(repositoryIdentity: snapshot.repositoryIdentity, info: info)],
            blocked: []
        )
    }

    private func dismissCleanupConfirmation() {
        showCleanupConfirmation = false
        pendingReadyUnits = []
        pendingBlockedUnits = []
    }

    private func runCleanup(units: [GitCleanupUnit]) {
        guard let snapshot = gitManager.worktreeSnapshot, !units.isEmpty else { return }
        dismissCleanupConfirmation()
        Task {
            _ = await actionCoordinator.sidePanel.performSidePanelCleanup(units: units, snapshot: snapshot)
        }
    }

    private func revealWorktree(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

#Preview("Side Panel Branch Management") {
    MainMenuPreviewHarness {
        SidePanelBranchManagementView(
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in },
            onCreateBranch: {},
            onRenameBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 640)
}
