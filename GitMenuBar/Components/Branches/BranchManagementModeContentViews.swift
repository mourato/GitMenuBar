import SwiftUI

enum BranchManagementMode: String, CaseIterable, Identifiable {
    case branches
    case worktrees
    case cleanup

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .branches:
            return "Branches"
        case .worktrees:
            return "Worktrees"
        case .cleanup:
            return "Cleanup"
        }
    }
}

struct BranchManagementListView: View {
    @Binding var mode: BranchManagementMode
    @Binding var query: String
    let branchInfos: [BranchInfo]
    let worktreeSnapshot: GitWorktreeSnapshot?
    let worktreeErrorMessage: String?
    @Binding var selectedCleanupIDs: Set<String>
    let onRevealWorktree: (String) -> Void
    let onCopyPath: (String) -> Void
    let onDismissError: () -> Void
    let branchRow: (BranchInfo) -> BranchManagementRowView

    private var localInfos: [BranchInfo] {
        filteredInfos { $0.isLocal }
    }

    private var remoteInfos: [BranchInfo] {
        filteredInfos { $0.isRemote }
    }

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            filterField
            Divider()
            content
        }
    }

    private var modePicker: some View {
        Picker("Management view", selection: $mode) {
            ForEach(BranchManagementMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityLabel("Branch management view")
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(filterPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(MacChromeTypography.body)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filterPlaceholder: String {
        switch mode {
        case .branches:
            return "Filter branches"
        case .worktrees:
            return "Filter worktrees or paths"
        case .cleanup:
            return "Filter local branches"
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            switch mode {
            case .branches:
                branchesContent
            case .worktrees:
                WorktreeManagementContentView(
                    snapshot: worktreeSnapshot,
                    errorMessage: worktreeErrorMessage,
                    query: query,
                    onReveal: onRevealWorktree,
                    onCopyPath: onCopyPath,
                    onDismissError: onDismissError
                )
            case .cleanup:
                CleanupManagementContentView(
                    snapshot: worktreeSnapshot,
                    errorMessage: worktreeErrorMessage,
                    query: query,
                    selectedIDs: $selectedCleanupIDs,
                    onDismissError: onDismissError,
                    onReveal: onRevealWorktree,
                    onCopyPath: onCopyPath
                )
            }
        }
        .frame(maxHeight: 460)
    }

    private var branchesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Local Branches")
            if localInfos.isEmpty {
                emptyHint
            } else {
                ForEach(localInfos) { branchRow($0) }
            }

            sectionHeader("Remote Branches")
            if remoteInfos.isEmpty {
                emptyHint
            } else {
                ForEach(remoteInfos) { branchRow($0) }
            }
        }
        .padding(16)
    }

    private func filteredInfos(matching predicate: (BranchInfo) -> Bool) -> [BranchInfo] {
        branchInfos
            .filter(predicate)
            .filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent {
                    return lhs.isCurrent
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(MacChromeTypography.sectionLabel)
            .foregroundStyle(.secondary)
    }

    private var emptyHint: some View {
        Text("No branches match your filter.")
            .font(MacChromeTypography.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

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
                .font(MacChromeTypography.caption)
                .foregroundStyle(.secondary)
                .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let snapshot {
                    Text("\(snapshot.worktrees.count) worktree\(snapshot.worktrees.count == 1 ? "" : "s")")
                        .font(MacChromeTypography.sectionLabel)
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

    private var localInfos: [GitBranchCleanupInfo] {
        guard let snapshot else { return [] }
        return snapshot.branches
            .filter { !$0.reference.isRemote }
            .filter { query.isEmpty || $0.reference.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.reference.name.localizedStandardCompare($1.reference.name) == .orderedAscending }
    }

    private var allLocalInfos: [GitBranchCleanupInfo] {
        guard let snapshot else { return [] }
        return snapshot.branches.filter { !$0.reference.isRemote }
    }

    private var eligibleCount: Int {
        allLocalInfos.filter(\.isEligible).count
    }

    private var unknownCount: Int {
        allLocalInfos.filter {
            if case .unknown = $0.status {
                return true
            } else {
                return false
            }
        }.count
    }

    private var blockedCount: Int {
        max(0, allLocalInfos.count - eligibleCount - unknownCount)
    }

    var body: some View {
        if let errorMessage {
            InlineStatusBannerView(
                banner: InlineStatusBanner(title: nil, message: errorMessage, style: .error),
                onDismiss: onDismissError
            )
            .padding(16)
        } else if let snapshot {
            VStack(alignment: .leading, spacing: 12) {
                summary(snapshot: snapshot)
                if localInfos.isEmpty {
                    Text("No local branches match your filter.")
                        .font(MacChromeTypography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(localInfos) { info in
                        cleanupRow(info)
                    }
                }
                CleanupWorktreeListView(
                    snapshot: snapshot,
                    query: query,
                    selectedIDs: $selectedIDs,
                    onReveal: onReveal,
                    onCopyPath: onCopyPath
                )
            }
            .padding(16)
        } else {
            Text("No cleanup analysis is available.")
                .font(MacChromeTypography.caption)
                .foregroundStyle(.secondary)
                .padding(16)
        }
    }

    private func summary(snapshot: GitWorktreeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Default branch: \(snapshot.defaultBranchName)", systemImage: "arrow.triangle.branch")
                    .font(MacChromeTypography.sectionLabel)
                Spacer()
                Text("Local refs")
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.analysisDescription)
                .font(MacChromeTypography.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                summaryCount(eligibleCount, title: "eligible", color: .green)
                summaryCount(blockedCount, title: "blocked", color: .orange)
                summaryCount(unknownCount, title: "unknown", color: .red)
            }
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Cleanup analysis against \(snapshot.defaultBranchName). "
                + "\(eligibleCount) eligible, \(blockedCount) blocked, \(unknownCount) unknown."
        )
    }

    private func summaryCount(_ count: Int, title: String, color: Color) -> some View {
        Label("\(count) \(title)", systemImage: "circle.fill")
            .font(MacChromeTypography.captionStrong)
            .foregroundStyle(color)
    }

    private func cleanupRow(_ info: GitBranchCleanupInfo) -> some View {
        HStack(spacing: 8) {
            if info.isEligible {
                Toggle(
                    "Select \(info.reference.name)",
                    isOn: Binding(
                        get: { selectedIDs.contains(GitCleanupTarget.localBranch(info).id) },
                        set: { selected in
                            let id = GitCleanupTarget.localBranch(info).id
                            if selected {
                                selectedIDs.insert(id)
                            } else {
                                selectedIDs.remove(id)
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
            } else {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(info.reference.name)
                    .font(MacChromeTypography.body)
                if let worktreePath = info.worktreePath {
                    Text("Checked out at \(worktreePath)")
                        .font(MacChromeTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let detail = statusDetail(for: info.status), info.worktreePath == nil {
                    Text(detail)
                        .font(MacChromeTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            CleanupStatusBadgeView(status: info.status)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(info.isEligible ? Color.clear : MacChromePalette.hoverFill())
        .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cleanupAccessibilityLabel(for: info))
    }
}
