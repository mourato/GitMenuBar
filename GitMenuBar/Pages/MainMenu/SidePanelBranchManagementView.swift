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

    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @State private var branchQuery = ""
    @State private var branchesExpanded = true
    @State private var worktreesExpanded = false
    @State private var cleanupExpanded = false
    @State private var deleteRemoteName: String?
    @State private var selectedCleanupIDs: Set<String> = []
    @State private var pendingCleanupUnits: [GitCleanupUnit] = []
    @State private var showCleanupConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            branchesGroup
            worktreesGroup
            cleanupGroup
        }
        .alert("Delete Remote Branch?", isPresented: Binding(
            get: { deleteRemoteName != nil },
            set: {
                if !$0 {
                    deleteRemoteName = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                guard let name = deleteRemoteName else { return }
                deleteRemoteName = nil
                Task { _ = await actionCoordinator.deleteRemoteSidePanelBranch(name) }
            }
            Button("Cancel", role: .cancel) { deleteRemoteName = nil }
        } message: {
            if let name = deleteRemoteName {
                Text("This will permanently delete 'origin/\(name)' on the remote. This cannot be undone.")
            }
        }
        .sheet(isPresented: $showCleanupConfirmation) {
            CleanupConfirmationView(
                units: pendingCleanupUnits,
                onCancel: dismissCleanupConfirmation,
                onConfirm: runCleanup
            )
        }
    }

    private var branchesGroup: some View {
        DisclosureGroup(isExpanded: $branchesExpanded) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                Text("Local Git reachability against \(gitManager.defaultBranchName.isEmpty ? "the default branch" : gitManager.defaultBranchName), not GitHub pull request status.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                filterField(query: $branchQuery, placeholder: "Filter branches")
                if !filteredLocalBranches.isEmpty {
                    Text("Local Branches")
                        .font(WorkbenchTypography.sectionLabel)
                    ForEach(filteredLocalBranches) { localManagementRow($0) }
                }
                if !filteredRemoteBranches.isEmpty {
                    Text("Remote Branches")
                        .font(WorkbenchTypography.sectionLabel)
                    ForEach(filteredRemoteBranches) { remoteManagementRow($0) }
                }
                if filteredLocalBranches.isEmpty, filteredRemoteBranches.isEmpty {
                    Text("No branches match your filter.")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    onCreateBranch()
                } label: {
                    Label("New Branch", systemImage: "plus")
                }
                .workbenchSecondary()
                .disabled(actionCoordinator.isBusy)
            }
        } label: {
            Text("Branches (\(gitManager.branchInfos.filter(\.isLocal).count))")
                .font(WorkbenchTypography.sectionLabel)
        }
    }

    private var worktreesGroup: some View {
        DisclosureGroup(isExpanded: $worktreesExpanded) {
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
            } else {
                Text("No cleanup analysis is available.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Worktrees (\(gitManager.worktreeSnapshot?.worktrees.count ?? 0))")
                .font(WorkbenchTypography.sectionLabel)
        }
    }

    private var cleanupGroup: some View {
        DisclosureGroup(isExpanded: $cleanupExpanded) {
            if let snapshot = gitManager.worktreeSnapshot {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                    if let progress = gitManager.cleanupProgress {
                        CleanupProgressView(progress: progress)
                    }
                    CleanupManagementContentView(
                        snapshot: snapshot,
                        errorMessage: nil,
                        query: branchQuery,
                        selectedIDs: $selectedCleanupIDs,
                        onDismissError: {},
                        onReveal: revealWorktree,
                        onCopyPath: copyPath,
                        onForceRemove: forceRemoveWorktree,
                        onCleanUnit: { unit in
                            presentCleanupConfirmation(units: [unit])
                        }
                    )
                    Button("Clean Selected") {
                        presentCleanupConfirmation(units: selectedCleanupUnits(snapshot))
                    }
                    .workbenchSecondary()
                    .disabled(actionCoordinator.isBusy || selectedCleanupUnits(snapshot).isEmpty)
                    .help(
                        selectedCleanupUnits(snapshot).isEmpty
                            ? "Select at least one safe branch first."
                            : "Review the selected branches and worktrees."
                    )
                }
            } else {
                Text("No cleanup analysis is available.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Cleanup")
                .font(WorkbenchTypography.sectionLabel)
        }
    }

    private func localManagementRow(_ info: BranchInfo) -> BranchManagementRowView {
        BranchManagementRowView(
            branch: info,
            onSwitch: { onRequestSwitchBranch(info.displayName) },
            onRename: { onRenameBranch(info.name) },
            onDelete: { onRequestDeleteBranch(info.name) },
            onPush: needsPush(info) ? {
                Task {
                    if info.trackingStatus == .noRemote {
                        _ = await actionCoordinator.publishSidePanelBranch(info.name)
                    } else {
                        _ = await actionCoordinator.pushSidePanelBranch(info.name)
                    }
                }
            } : nil,
            onMerge: gitManager.unmergedIntoDefaultBranches.contains(info.name) && !info.isCurrent ? {
                Task { _ = await actionCoordinator.mergeSidePanelBranch(info.name) }
            } : nil,
            onDeleteRemote: nil,
            onCheckoutLocally: nil
        )
    }

    private func remoteManagementRow(_ info: BranchInfo) -> BranchManagementRowView {
        BranchManagementRowView(
            branch: info,
            onSwitch: {},
            onRename: {},
            onDelete: {},
            onPush: nil,
            onMerge: nil,
            onDeleteRemote: { deleteRemoteName = info.name },
            onCheckoutLocally: {
                Task { _ = await actionCoordinator.checkoutRemoteSidePanelBranch(info.name) }
            }
        )
    }

    private var filteredLocalBranches: [BranchInfo] {
        filteredBranches { $0.isLocal }
    }

    private var filteredRemoteBranches: [BranchInfo] {
        filteredBranches { $0.isRemote }
    }

    private func filteredBranches(matching predicate: (BranchInfo) -> Bool) -> [BranchInfo] {
        gitManager.branchInfos
            .filter(predicate)
            .filter { branchQuery.isEmpty || $0.displayName.localizedCaseInsensitiveContains(branchQuery) }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent {
                    return lhs.isCurrent
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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

    private func needsPush(_ info: BranchInfo) -> Bool {
        switch info.trackingStatus {
        case .noRemote, .ahead, .diverged:
            true
        case .upToDate, .behind, .unknown:
            false
        }
    }

    private func selectedCleanupUnits(_ snapshot: GitWorktreeSnapshot) -> [GitCleanupUnit] {
        snapshot.cleanupUnits.filter { selectedCleanupIDs.contains($0.id) }
    }

    private func presentCleanupConfirmation(units: [GitCleanupUnit]) {
        guard !units.isEmpty else { return }
        pendingCleanupUnits = units
        showCleanupConfirmation = true
    }

    private func forceRemoveWorktree(_ info: GitWorktreeCleanupInfo) {
        guard let snapshot = gitManager.worktreeSnapshot, snapshot.canForceRemove(info) else { return }
        presentCleanupConfirmation(units: [
            GitCleanupUnit.forceWorktreeRemoval(repositoryIdentity: snapshot.repositoryIdentity, info: info)
        ])
    }

    private func dismissCleanupConfirmation() {
        showCleanupConfirmation = false
        pendingCleanupUnits = []
    }

    private func runCleanup() {
        guard let snapshot = gitManager.worktreeSnapshot else { return }
        let units = pendingCleanupUnits
        guard !units.isEmpty else { return }
        dismissCleanupConfirmation()
        Task {
            _ = await actionCoordinator.performSidePanelCleanup(units: units, snapshot: snapshot)
            selectedCleanupIDs.subtract(Set(units.map(\.id)))
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
