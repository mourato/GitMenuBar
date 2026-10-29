import AppKit
import SwiftUI

// swiftlint:disable file_length

private struct BranchListMotionState: Equatable {
    let visibleIDs: [String]
    let collapsedIDs: [String]
    let filter: BranchFilter
}

/// Unified branch management surface hosted in the inspector.
/// Integrates branch filtering, reachability analysis against the default branch,
/// inline cleanup actions and review banners, worktree inspection, and branch operations
/// using `BranchListResolver`.
struct SidePanelBranchManagementView: View {
    let onRequestDeleteBranch: (String) -> Void
    let onRequestSwitchBranch: (String) -> Void
    let onCreateBranch: () -> Void
    let onRenameBranch: (String) -> Void

    @Environment(GitManager.self) private var gitManager
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var now = Date()
    @State private var branchQuery = ""
    @State private var filter: BranchFilter = .all
    @State private var branchesExpanded = true
    @State private var worktreesExpanded = false
    @State private var moreMergedExpanded = false
    @State private var deleteRemoteBranch: BranchInfo?
    @State private var pendingReadyUnits: [GitCleanupUnit] = []
    @State private var pendingBlockedUnits: [GitCleanupUnit] = []
    @State private var pendingCleanupSnapshot: GitWorktreeSnapshot?
    @State private var showCleanupConfirmation = false

    init(
        onRequestDeleteBranch: @escaping (String) -> Void,
        onRequestSwitchBranch: @escaping (String) -> Void,
        onCreateBranch: @escaping () -> Void,
        onRenameBranch: @escaping (String) -> Void,
        initialFilter: BranchFilter = .all,
        initialQuery: String = ""
    ) {
        self.onRequestDeleteBranch = onRequestDeleteBranch
        self.onRequestSwitchBranch = onRequestSwitchBranch
        self.onCreateBranch = onCreateBranch
        self.onRenameBranch = onRenameBranch
        _filter = State(initialValue: initialFilter)
        _branchQuery = State(initialValue: initialQuery)
    }

    private var defaultBranchDisplayName: String {
        gitManager.defaultBranchName.isEmpty ? "the default branch" : gitManager.defaultBranchName
    }

    private var listModel: BranchListModel {
        BranchListResolver.resolve(
            branches: gitManager.branchInfos,
            snapshot: gitManager.worktreeSnapshot,
            query: branchQuery,
            filter: filter,
            now: now
        )
    }

    /// First management unit per branch name; built once per body pass for row lookups.
    private var managementUnitsByBranch: [String: GitCleanupUnit] {
        Dictionary(
            (gitManager.worktreeSnapshot?.managementUnits ?? []).map { ($0.branch.reference.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        let model = listModel
        let units = managementUnitsByBranch
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            branchesGroup(model: model, units: units)
        }
        .onAppear {
            now = Date()
        }
        .onChange(of: gitManager.branchInfos) { _, _ in
            now = Date()
        }
        .onChange(of: gitManager.worktreeSnapshot) { _, _ in
            now = Date()
        }
        .alert("Delete Remote Branch?", isPresented: Binding(
            get: { deleteRemoteBranch != nil },
            set: {
                if !$0 {
                    deleteRemoteBranch = nil
                }
            }
        )) {
            Button("Delete", role: .destructive, action: confirmDeleteRemote)
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
                onConfirm: { unitsToClean in runCleanup(units: unitsToClean) }
            )
        }
    }

    private func branchesGroup(model: BranchListModel, units: [String: GitCleanupUnit]) -> some View {
        DisclosureGroup(isExpanded: $branchesExpanded) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                headerCaption
                filterField(query: $branchQuery, placeholder: "Filter branches")
                BranchFilterChipsView(filter: $filter, model: model)
                if let progress = gitManager.cleanupProgress {
                    CleanupProgressView(progress: progress)
                }
                if model.readyCount + model.blockedCount > 0 {
                    cleanupBanner(model: model)
                }
                if let currentRow = model.local.first(where: \.branch.isCurrent) {
                    pinnedCurrentBranchRow(currentRow, units: units)
                }
                localSection(model: model, units: units)
                remoteSection(model: model)
                if isNoMatches(model: model) {
                    emptyFilterState
                }
                footer
                if worktreesExpanded {
                    worktreesContent
                }
            }
            .animation(
                WorkbenchMotion.swap,
                value: BranchListMotionState(
                    visibleIDs: model.visible.map(\.id),
                    collapsedIDs: model.collapsedMerged.map(\.id),
                    filter: filter
                )
            )
            .adaptiveMotion()
        } label: {
            Text("Branches")
                .font(WorkbenchTypography.sectionLabel)
        }
    }

    private var isFiltering: Bool {
        filter != .all || !branchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isNoMatches(model: BranchListModel) -> Bool {
        isFiltering && model.local.isEmpty && model.remoteGroups.isEmpty && model.ungroupedRemote.isEmpty
    }

    private var emptyFilterState: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Text("No branches match")
                .font(WorkbenchTypography.sectionLabel)
            Text("Clear the filter or search")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            Button("Clear", action: clearFilters)
                .workbenchSecondary()
                .frame(minHeight: WorkbenchMetrics.minimumHitTarget)
                .contentShape(Rectangle())
                .accessibilityLabel("Clear branch filter and search")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, WorkbenchMetrics.compactSpacing)
        .padding(.horizontal, WorkbenchMetrics.rowContentInset)
    }

    private func clearFilters() {
        withAnimation(WorkbenchMotion.swap) {
            branchQuery = ""
            filter = .all
        }
    }

    /// Pass `count` only when no filter chip already shows the same number.
    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        var label = Text(title)
        if let count {
            label = label + Text(" · ") + Text("\(count)").monospacedDigit()
        }
        return label
            .font(WorkbenchTypography.captionStrong)
            .textCase(.uppercase)
            .tracking(WorkbenchTypography.tracking(for: WorkbenchTypography.caption))
            .foregroundStyle(.secondary)
            .padding(.leading, WorkbenchMetrics.rowContentInset)
    }

    private var headerCaption: some View {
        Text("vs \(defaultBranchDisplayName) · local")
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
            .help("Local Git reachability against \(defaultBranchDisplayName), not GitHub pull request status.")
    }

    /// Shows the Review entry only when something is ready; with none ready, states the blocked count.
    private func cleanupBanner(model: BranchListModel) -> some View {
        let hasReady = model.readyCount > 0
        let fill = hasReady
            ? WorkbenchPalette.successFill(contrast: colorSchemeContrast)
            : WorkbenchPalette.hoverFill()
        return HStack(alignment: .center, spacing: WorkbenchMetrics.compactSpacing) {
            if hasReady {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    Text("\(model.readyCount) ready to clean")
                        .font(WorkbenchTypography.sectionLabel)
                    Text("\(model.blockedCount) blocked")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(model.readyCount) ready to clean, \(model.blockedCount) blocked")
                Spacer(minLength: WorkbenchMetrics.compactSpacing)
                Button("Review") {
                    guard let snapshot = gitManager.worktreeSnapshot else { return }
                    let matching = snapshot.managementUnits(matching: branchQuery)
                    presentCleanupConfirmation(
                        snapshot: snapshot,
                        ready: matching.filter(\.canPrimaryClean),
                        blocked: matching.filter { !$0.canPrimaryClean }
                    )
                }
                .workbenchSecondary()
                .frame(minHeight: WorkbenchMetrics.minimumHitTarget)
                .contentShape(Rectangle())
                .disabled(actionCoordinator.isBusy)
                .help("Review branches and worktrees ready to clean")
            } else {
                Text("\(model.blockedCount) blocked")
                    .font(WorkbenchTypography.sectionLabel)
                    .help("Nothing is ready to clean. Blocked branches and worktrees need attention first.")
                    .accessibilityLabel("\(model.blockedCount) blocked, nothing ready to clean")
                Spacer(minLength: WorkbenchMetrics.compactSpacing)
            }
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .background(fill, in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
    }

    /// Current branch row, pinned only while it matches the active query and filter.
    /// Neutral border keeps the accent for the checkmark and the selected filter chip.
    private func pinnedCurrentBranchRow(
        _ current: BranchListRow,
        units: [String: GitCleanupUnit]
    ) -> some View {
        localManagementRow(current.branch, unit: units[current.branch.name], badgeStatus: current.cleanupStatus)
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .strokeBorder(WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast), lineWidth: 1)
            )
            .transition(.opacity)
    }

    @ViewBuilder
    private func localSection(model: BranchListModel, units: [String: GitCleanupUnit]) -> some View {
        let nonCurrentVisible = model.visible.filter { !$0.branch.isCurrent }
        let totalCount = nonCurrentVisible.count + model.collapsedMerged.count

        if totalCount > 0 {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                sectionHeader("LOCAL")

                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    ForEach(nonCurrentVisible) { row in
                        localManagementRow(row.branch, unit: units[row.branch.name], badgeStatus: row.cleanupStatus)
                            .transition(.opacity)
                    }
                }

                if model.hasCollapsedMerged {
                    DisclosureGroup(isExpanded: $moreMergedExpanded) {
                        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                            ForEach(model.collapsedMerged) { row in
                                localManagementRow(row.branch, unit: units[row.branch.name], badgeStatus: row.cleanupStatus)
                                    .transition(.opacity)
                            }
                        }
                    } label: {
                        Text("\(model.collapsedMerged.count) more merged branches")
                            .font(WorkbenchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, WorkbenchMetrics.rowContentInset)
                }
            }
        }
    }

    @ViewBuilder
    private func remoteSection(model: BranchListModel) -> some View {
        let remoteTotalCount = model.remoteGroups.reduce(0) { $0 + $1.branches.count } + model.ungroupedRemote.count

        if remoteTotalCount > 0 {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                sectionHeader("REMOTE", count: remoteTotalCount)

                ForEach(model.remoteGroups) { group in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                            ForEach(group.branches) { branch in
                                remoteManagementRow(branch).transition(.opacity)
                            }
                        }
                    } label: {
                        HStack(spacing: WorkbenchMetrics.compactSpacing) {
                            Text(group.name).font(WorkbenchTypography.body).foregroundStyle(.primary)
                            Text("\(group.branches.count)")
                                .font(WorkbenchTypography.caption).monospacedDigit().foregroundStyle(.secondary)
                                .padding(.horizontal, WorkbenchMetrics.chipSpacing)
                                .padding(.vertical, WorkbenchMetrics.microSpacing / 2)
                                .background(Capsule().fill(WorkbenchPalette.hoverFill()))
                        }
                    }
                    .padding(.leading, WorkbenchMetrics.rowContentInset)
                }

                ForEach(model.ungroupedRemote) { branch in
                    remoteManagementRow(branch).transition(.opacity)
                }
            }
        } else if filter != .all, !isNoMatches(model: model), gitManager.branchInfos.contains(where: \.isRemote) {
            Text("Remote branches hidden by filter")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, WorkbenchMetrics.rowContentInset)
        }
    }

    private var footer: some View {
        let worktreeCount = gitManager.worktreeSnapshot?.worktrees.count ?? 0
        return HStack {
            Button("New Branch", systemImage: "plus", action: onCreateBranch)
                .workbenchSecondary()
                .disabled(actionCoordinator.isBusy)
            Spacer()
            Button {
                withAnimation(WorkbenchMotion.swap) { worktreesExpanded.toggle() }
            } label: {
                HStack(spacing: WorkbenchMetrics.microSpacing) {
                    Text("Worktrees \(worktreeCount)")
                    Image(systemName: "chevron.right").rotationEffect(.degrees(worktreesExpanded ? 90 : 0))
                }
                .frame(minHeight: WorkbenchMetrics.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .workbenchGhost()
            .disabled(actionCoordinator.isBusy)
            .accessibilityLabel("Worktrees, \(worktreeCount)")
            .accessibilityValue(worktreesExpanded ? "Expanded" : "Collapsed")
        }
    }

    @ViewBuilder
    private var worktreesContent: some View {
        if let snapshot = gitManager.worktreeSnapshot {
            WorktreeManagementContentView(
                snapshot: snapshot,
                errorMessage: nil,
                query: branchQuery,
                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: $0)]) },
                onCopyPath: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString($0, forType: .string)
                },
                onRemove: removeWorktree,
                onForceRemove: forceRemoveWorktree,
                onDismissError: {}
            )
            .transition(.opacity)
        } else {
            Text("No cleanup analysis is available.").font(WorkbenchTypography.caption).foregroundStyle(.secondary)
        }
    }

    private func localManagementRow(
        _ info: BranchInfo,
        unit: GitCleanupUnit?,
        badgeStatus: BranchCleanupBadgeStatus? = nil
    ) -> some View {
        BranchManagementRowView(
            branch: info,
            onSwitch: { onRequestSwitchBranch(info.displayName) },
            onRename: { onRenameBranch(info.name) },
            onDelete: deleteBranchAction(for: info, unit: unit),
            onPush: needsPush(info) ? { pushBranch(info) } : nil,
            onMerge: canMerge(info) ? { mergeBranch(info) } : nil,
            cleanupStatus: mapCleanupStatus(badgeStatus),
            worktreeStatus: resolvedWorktreeStatus(unit: unit, badgeStatus: badgeStatus),
            blockedReason: resolvedBlockedReason(unit: unit, badgeStatus: badgeStatus),
            onCleanUnit: cleanAction(for: unit),
            onRemoveWorktree: removeWorktreeAction(for: unit)
        )
        .disabled(actionCoordinator.isBusy)
    }

    private func resolvedWorktreeStatus(
        unit: GitCleanupUnit?,
        badgeStatus: BranchCleanupBadgeStatus?
    ) -> GitWorktreeCleanupStatus? {
        if let status = unit?.worktree?.status {
            switch status {
            case .dirty, .locked: return status
            default: break
            }
        }
        return badgeStatus == .dirty ? .dirty : nil
    }

    private func resolvedBlockedReason(
        unit: GitCleanupUnit?,
        badgeStatus: BranchCleanupBadgeStatus?
    ) -> String? {
        if case let .blocked(reason) = badgeStatus {
            return reason
        }
        if let worktree = unit?.worktree, case let .locked(reason) = worktree.status {
            return "Locked: \(reason)"
        }
        return nil
    }

    private func cleanAction(for unit: GitCleanupUnit?) -> (() -> Void)? {
        guard let unit else { return nil }
        return {
            guard let current = gitManager.worktreeSnapshot else { return }
            presentCleanupConfirmation(
                snapshot: current,
                ready: unit.canPrimaryClean ? [unit] : [],
                blocked: unit.canPrimaryClean ? [] : [unit]
            )
        }
    }

    private func removeWorktreeAction(for unit: GitCleanupUnit?) -> (() -> Void)? {
        guard let unit,
              let status = unit.worktree?.status,
              status != .main,
              status != .current,
              let removeUnit = unit.removingWorktreeOnly()
        else { return nil }
        return {
            guard let current = gitManager.worktreeSnapshot else { return }
            presentCleanupConfirmation(
                snapshot: current,
                ready: removeUnit.canPrimaryClean ? [removeUnit] : [],
                blocked: removeUnit.canPrimaryClean ? [] : [removeUnit]
            )
        }
    }

    /// Branches with a management unit delete through the cleanup sheet (risk gate applies).
    /// Without a unit, the legacy confirmation stays. Hidden while Git requires worktree removal first.
    private func deleteBranchAction(for info: BranchInfo, unit: GitCleanupUnit?) -> (() -> Void)? {
        guard let unit else {
            return { onRequestDeleteBranch(info.name) }
        }
        let branchOnly = unit.deletingBranchOnly()
        guard branchOnly.canPrimaryClean else { return nil }
        return {
            guard let snapshot = gitManager.worktreeSnapshot else { return }
            presentCleanupConfirmation(snapshot: snapshot, ready: [branchOnly], blocked: [])
        }
    }

    private func canMerge(_ info: BranchInfo) -> Bool {
        gitManager.unmergedIntoDefaultBranches.contains(info.name) && !info.isCurrent
    }

    private func pushBranch(_ info: BranchInfo) {
        Task {
            if info.trackingStatus == .noRemote {
                _ = await actionCoordinator.sidePanel.publishSidePanelBranch(info.name)
            } else {
                _ = await actionCoordinator.sidePanel.pushSidePanelBranch(info.name)
            }
        }
    }

    private func mergeBranch(_ info: BranchInfo) {
        Task { _ = await actionCoordinator.sidePanel.mergeSidePanelBranch(info.name) }
    }

    private func remoteManagementRow(_ info: BranchInfo) -> some View {
        BranchManagementRowView(
            branch: info,
            onSwitch: {},
            onRename: {},
            onDeleteRemote: { deleteRemoteBranch = info },
            onCheckoutLocally: {
                Task {
                    _ = await actionCoordinator.sidePanel.checkoutRemoteSidePanelBranch(
                        info.name,
                        remoteName: info.remoteName ?? "origin"
                    )
                }
            }
        )
        .disabled(actionCoordinator.isBusy)
    }

    private func mapCleanupStatus(_ status: BranchCleanupBadgeStatus?) -> GitBranchCleanupStatus? {
        status == .merged ? .mergedIntoDefault : nil
    }

    private func filterField(query: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: query)
                .textFieldStyle(.plain)
                .font(WorkbenchTypography.body)
            if !query.wrappedValue.isEmpty {
                Button {
                    query.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
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

    private func needsPush(_ info: BranchInfo) -> Bool {
        switch info.trackingStatus {
        case .noRemote, .ahead, .diverged:
            true
        default:
            false
        }
    }

    private func presentCleanupConfirmation(
        snapshot: GitWorktreeSnapshot,
        ready: [GitCleanupUnit],
        blocked: [GitCleanupUnit] = []
    ) {
        guard !ready.isEmpty || !blocked.isEmpty else { return }
        pendingCleanupSnapshot = snapshot
        pendingReadyUnits = ready
        pendingBlockedUnits = blocked
        showCleanupConfirmation = true
    }

    private func removeWorktree(_ info: GitWorktreeCleanupInfo) {
        guard let snapshot = gitManager.worktreeSnapshot, let unit = snapshot.worktreeRemovalUnit(for: info) else { return }
        presentCleanupConfirmation(snapshot: snapshot, ready: [unit], blocked: [])
    }

    private func forceRemoveWorktree(_ info: GitWorktreeCleanupInfo) {
        guard let snapshot = gitManager.worktreeSnapshot, snapshot.canForceRemove(info) else { return }
        presentCleanupConfirmation(
            snapshot: snapshot,
            ready: [GitCleanupUnit.forceWorktreeRemoval(repositoryIdentity: snapshot.repositoryIdentity, info: info)],
            blocked: []
        )
    }

    private func dismissCleanupConfirmation() {
        showCleanupConfirmation = false
        pendingReadyUnits = []
        pendingBlockedUnits = []
        pendingCleanupSnapshot = nil
    }

    private func runCleanup(units: [GitCleanupUnit]) {
        guard let snapshot = pendingCleanupSnapshot ?? gitManager.worktreeSnapshot, !units.isEmpty else { return }
        dismissCleanupConfirmation()
        Task { _ = await actionCoordinator.sidePanel.performSidePanelCleanup(units: units, snapshot: snapshot) }
    }

    private func confirmDeleteRemote() {
        guard let branch = deleteRemoteBranch else { return }
        deleteRemoteBranch = nil
        Task {
            _ = await actionCoordinator.sidePanel.deleteRemoteSidePanelBranch(
                branch.name,
                remoteName: branch.remoteName ?? "origin"
            )
        }
    }
}
