import SwiftUI

struct WorktreeManagementContentView: View {
    let snapshot: GitWorktreeSnapshot?
    let errorMessage: String?
    let query: String
    let onReveal: (String) -> Void
    let onCopyPath: (String) -> Void
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
                        onCopyPath: { onCopyPath(info.worktree.path) }
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
    let onCleanUnit: (GitCleanupUnit) -> Void

    @State private var diagnosticsExpanded = false

    private var units: [GitCleanupUnit] {
        guard let snapshot else { return [] }
        return snapshot.cleanupUnits.filter { unit in
            query.isEmpty
                || unit.branch.reference.name.localizedCaseInsensitiveContains(query)
                || (unit.worktree?.worktree.path.localizedCaseInsensitiveContains(query) ?? false)
        }.sorted { $0.branch.reference.name.localizedStandardCompare($1.branch.reference.name) == .orderedAscending }
    }

    private var diagnosticBranches: [GitBranchCleanupInfo] {
        guard let snapshot else { return [] }
        let candidateNames = Set(snapshot.cleanupUnits.map(\.branch.reference.name))
        return snapshot.branches
            .filter { !$0.reference.isRemote && !$0.isEligible && !candidateNames.contains($0.reference.name) }
            .filter { query.isEmpty || $0.reference.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.reference.name.localizedStandardCompare($1.reference.name) == .orderedAscending }
    }

    private var diagnosticWorktrees: [GitWorktreeCleanupInfo] {
        guard let snapshot else { return [] }
        let candidatePaths = Set(
            snapshot.cleanupUnits.compactMap { $0.worktree?.worktree.path }.map(GitRepositoryContext.normalizedPath)
        )
        return snapshot.worktrees
            .filter {
                !$0.status.isEligible
                    && !candidatePaths.contains(GitRepositoryContext.normalizedPath($0.worktree.path))
            }
            .filter {
                query.isEmpty
                    || $0.worktree.path.localizedCaseInsensitiveContains(query)
                    || ($0.worktree.branchName?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.worktree.path.localizedStandardCompare($1.worktree.path) == .orderedAscending }
    }

    private var diagnosticCount: Int {
        diagnosticBranches.count + diagnosticWorktrees.count
    }

    private var eligibleCount: Int {
        snapshot?.branchCandidateCount ?? 0
    }

    private var unknownCount: Int {
        snapshot?.branches.filter {
            if case .unknown = $0.status {
                true
            } else {
                false
            }
        }.count ?? 0
    }

    private var blockedCount: Int {
        max(0, (snapshot?.branches.filter { !$0.reference.isRemote }.count ?? 0) - eligibleCount - unknownCount)
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
                if units.isEmpty, diagnosticCount == 0 {
                    Text("No branches match your filter.")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    eligibleSection
                    if diagnosticCount > 0 {
                        diagnosticsSection
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

    private var eligibleSection: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            Text("Safe to clean")
                .font(WorkbenchTypography.sectionLabel)
                .foregroundStyle(.secondary)
            if units.isEmpty {
                Text("No local branches are merged into \(defaultBranchName).")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(units) { unit in
                    cleanupRow(unit)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        DisclosureGroup(isExpanded: $diagnosticsExpanded) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                Text("These local branches and worktrees are not safe to remove yet.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                ForEach(diagnosticBranches) { info in
                    diagnosticBranchRow(info)
                }
                ForEach(diagnosticWorktrees) { info in
                    WorktreeManagementRowView(
                        info: info,
                        onReveal: { onReveal(info.worktree.path) },
                        onCopyPath: { onCopyPath(info.worktree.path) }
                    )
                }
            }
            .padding(.top, WorkbenchMetrics.microSpacing)
        } label: {
            Text("Not eligible (\(diagnosticCount))")
                .font(WorkbenchTypography.sectionLabel)
        }
        .accessibilityHint("Shows why branches and worktrees cannot be cleaned yet.")
    }

    private func summary(snapshot: GitWorktreeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            HStack {
                Label("Compared to \(snapshot.defaultBranchName)", systemImage: "arrow.triangle.branch")
                    .font(WorkbenchTypography.sectionLabel)
                Spacer(minLength: WorkbenchMetrics.compactSpacing)
                Text("Local only")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Text(
                "A branch is safe to clean when its tip is already in \(snapshot.defaultBranchName). "
                    + "Linked worktrees are removed before their branches."
            )
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                summaryCount(eligibleCount, title: "safe", color: .green)
                summaryCount(blockedCount, title: "not eligible", color: .orange)
                summaryCount(unknownCount, title: "unknown", color: .red)
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
                + "\(eligibleCount) safe, \(blockedCount) not eligible, \(unknownCount) unknown."
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

            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(unit.branch.reference.name)
                    .font(WorkbenchTypography.body)
                    .lineLimit(1)
                Text(eligibleDetail(for: unit))
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

            CleanupStatusBadgeView(status: GitBranchCleanupStatus.mergedIntoDefault)

            Button("Clean") {
                onCleanUnit(unit)
            }
            .controlSize(.small)
            .workbenchSecondary()
            .accessibilityLabel("Clean \(unit.branch.reference.name)")
            .accessibilityHint(
                unit.isPaired
                    ? "Reviews removing the linked worktree, then the merged branch."
                    : "Reviews deleting the merged local branch."
            )
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func diagnosticBranchRow(_ info: GitBranchCleanupInfo) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(info.reference.name)
                    .font(WorkbenchTypography.body)
                    .lineLimit(1)
                if let worktreePath = info.worktreePath {
                    Text("Checked out at \(worktreePath)")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let detail = statusDetail(for: info.status), info.worktreePath == nil {
                    Text(detail)
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

            CleanupStatusBadgeView(status: info.status)
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .background(WorkbenchPalette.hoverFill())
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cleanupAccessibilityLabel(for: info))
    }

    private func eligibleDetail(for unit: GitCleanupUnit) -> String {
        if let worktree = unit.worktree {
            return "Merged into \(defaultBranchName). Removes \(worktree.worktree.path) first."
        }
        return "Merged into \(defaultBranchName)."
    }
}
