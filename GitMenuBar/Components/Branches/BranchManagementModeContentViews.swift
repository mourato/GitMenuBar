import SwiftUI

struct WorktreeManagementContentView: View {
    let snapshot: GitWorktreeSnapshot?
    let errorMessage: String?
    let query: String
    let onReveal: (String) -> Void
    let onCopyPath: (String) -> Void
    let onForceRemove: ((GitWorktreeCleanupInfo) -> Void)?
    let onDismissError: () -> Void
    private var filteredWorktrees: [GitWorktreeCleanupInfo] {
        guard let snapshot else { return [] }
        return snapshot.worktrees
            .filter { info in
                guard !query.isEmpty else { return true }
                return info.worktree.path.localizedCaseInsensitiveContains(query)
                    || (info.worktree.branchName?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.worktree.path.localizedStandardCompare($1.worktree.path) == .orderedAscending }
    }

    var body: some View {
        if let errorMessage {
            InlineStatusBannerView(
                banner: InlineStatusBanner(title: nil, message: errorMessage, style: .error),
                onDismiss: onDismissError
            )
            .padding(16)
        } else if filteredWorktrees.isEmpty {
            Text("No worktrees match your filter.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let snapshot {
                    Text("\(snapshot.worktrees.count) worktree\(snapshot.worktrees.count == 1 ? "" : "s")")
                        .font(WorkbenchTypography.sectionLabel)
                        .foregroundStyle(.secondary)
                }
                ForEach(filteredWorktrees) { info in
                    WorktreeManagementRowView(
                        info: info,
                        onReveal: { onReveal(info.worktree.path) },
                        onCopyPath: { onCopyPath(info.worktree.path) },
                        onForceRemove: snapshot?.canForceRemove(info) == true
                            ? onForceRemove.map { handler in { handler(info) } }
                            : nil
                    )
                }
            }
            .padding(16)
        }
    }
}

struct CleanupManagementContentView: View {
    let snapshot: GitWorktreeSnapshot?
    let errorMessage: String?
    let query: String
    @Binding var selectedIDs: Set<String>
    let onDismissError: () -> Void
    let onReveal: (String) -> Void
    let onCopyPath: (String) -> Void
    let onForceRemove: ((GitWorktreeCleanupInfo) -> Void)?
    let onCleanUnit: (GitCleanupUnit) -> Void
    let onDeleteBranch: (GitCleanupUnit) -> Void
    let onRemoveWorktree: (GitCleanupUnit) -> Void

    private var units: [GitCleanupUnit] {
        guard let snapshot else { return [] }
        return snapshot.managementUnits.filter { unit in
            query.isEmpty
                || unit.branch.reference.name.localizedCaseInsensitiveContains(query)
                || (unit.worktree?.worktree.path.localizedCaseInsensitiveContains(query) ?? false)
        }.sorted {
            $0.branch.reference.name.localizedStandardCompare($1.branch.reference.name) == .orderedAscending
        }
    }

    private var actionableCount: Int {
        units.filter(\.canPrimaryClean).count
    }

    private var defaultBranchName: String {
        snapshot?.defaultBranchName ?? "the default branch"
    }

    var body: some View {
        if let errorMessage {
            InlineStatusBannerView(
                banner: InlineStatusBanner(title: nil, message: errorMessage, style: .error),
                onDismiss: onDismissError
            )
            .padding(16)
        } else if let snapshot {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
                summary(snapshot: snapshot)
                if units.isEmpty {
                    Text("No branches or worktrees match your filter.")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Work units")
                        .font(WorkbenchTypography.sectionLabel)
                        .foregroundStyle(.secondary)
                    ForEach(units) { unit in
                        cleanupRow(unit)
                    }
                }
            }
            .padding(16)
        } else {
            Text("No cleanup analysis is available.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .padding(16)
        }
    }

    private func summary(snapshot: GitWorktreeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            HStack {
                Label("Compared to \(snapshot.defaultBranchName)", systemImage: "arrow.triangle.branch")
                    .font(WorkbenchTypography.sectionLabel)
                Spacer(minLength: WorkbenchMetrics.compactSpacing)
                Text("Branches + worktrees")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Text(
                "Each row is one work unit. Clean removes a linked worktree before its branch; "
                    + "already cherry-picked branches count as merged."
            )
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                summaryCount(actionableCount, title: "ready", color: .green)
                summaryCount(units.count - actionableCount, title: "blocked", color: .orange)
            }
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Cleanup analysis against \(snapshot.defaultBranchName). "
                + "\(actionableCount) work units ready, \(units.count - actionableCount) blocked."
        )
    }

    private func summaryCount(_ count: Int, title: String, color: Color) -> some View {
        Label("\(count) \(title)", systemImage: "circle.fill")
            .font(WorkbenchTypography.captionStrong)
            .foregroundStyle(color)
    }

    private func cleanupRow(_ unit: GitCleanupUnit) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Toggle(
                "Select cleanup unit \(unit.branch.reference.name)",
                isOn: Binding(
                    get: { selectedIDs.contains(unit.id) },
                    set: { selected in
                        if selected {
                            selectedIDs.insert(unit.id)
                        } else {
                            selectedIDs.remove(unit.id)
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!unit.canPrimaryClean)

            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(unit.worktree?.worktree.branchName ?? unit.branch.reference.name)
                    .font(WorkbenchTypography.body)
                    .lineLimit(1)
                Text(detail(for: unit))
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

            if let worktree = unit.worktree {
                CleanupStatusBadgeView(status: worktree.status)
            } else {
                CleanupStatusBadgeView(status: unit.branch.status)
            }

            Button(unit.isWorktreeOnlyAction ? "Remove" : "Clean") {
                onCleanUnit(unit)
            }
            .controlSize(.small)
            .workbenchSecondary()
            .disabled(!unit.canPrimaryClean)
            .accessibilityLabel(primaryActionLabel(for: unit))
            .accessibilityHint(
                unit.isPaired
                    ? "Reviews removing the linked worktree, then the branch."
                    : unit.isWorktreeOnlyAction
                    ? "Reviews removing this worktree and keeping its branch."
                    : "Reviews deleting this local branch."
            )

            Menu {
                if let worktree = unit.worktree {
                    Button("Reveal in Finder") { onReveal(worktree.worktree.path) }
                    Button("Copy Path") { onCopyPath(worktree.worktree.path) }
                }
                if !unit.branch.reference.isRemote, unit.mode != .removeWorktree, unit.mode != .forceRemoveWorktree {
                    if unit.worktree == nil {
                        Button("Delete Branch", role: .destructive) {
                            onDeleteBranch(unit.deletingBranchOnly())
                        }
                        .disabled(!unit.canPrimaryClean)
                    } else {
                        Button("Delete Branch") {}
                            .disabled(true)
                    }
                }
                if let worktree = unit.worktree, let remove = unit.removingWorktreeOnly() {
                    Divider()
                    Button("Remove Worktree", role: .destructive) {
                        onRemoveWorktree(remove)
                    }
                    .disabled(!remove.canPrimaryClean)
                    if snapshot?.canForceRemove(worktree) == true, let onForceRemove {
                        Button("Force Remove Worktree", role: .destructive) { onForceRemove(worktree) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(WorkbenchTypography.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Actions for \(unit.branch.reference.name)")
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func detail(for unit: GitCleanupUnit) -> String {
        let branchDetail: String = switch unit.branch.status {
        case .protected, .current, .unknown:
            statusDetail(for: unit.branch.status) ?? "Branch status is unavailable."
        default:
            unit.branch.isMergedIntoDefault
                ? "Merged or cherry-picked into \(defaultBranchName)."
                : statusDetail(for: unit.branch.status) ?? "Branch is not eligible for cleanup."
        }

        if let worktree = unit.worktree {
            let worktreeDetail = worktreeStatusDetail(for: worktree.status)
            if unit.isWorktreeOnlyAction {
                return "\(worktreeDetail) Branch is kept."
            }
            return "\(branchDetail) \(worktreeDetail) Removes \(worktree.worktree.path) first."
        }
        return branchDetail
    }

    private func primaryActionLabel(for unit: GitCleanupUnit) -> String {
        if unit.isWorktreeOnlyAction {
            return "Remove worktree \(unit.branch.reference.name)"
        }
        if unit.isPaired {
            return "Clean branch and worktree \(unit.branch.reference.name)"
        }
        return "Delete branch \(unit.branch.reference.name)"
    }
}
