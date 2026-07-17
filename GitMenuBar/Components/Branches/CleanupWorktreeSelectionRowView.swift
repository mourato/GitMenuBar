import SwiftUI

struct CleanupWorktreeSelectionRowView: View {
    let info: GitWorktreeCleanupInfo
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(
                "Select worktree \(info.worktree.branchName ?? "detached")",
                isOn: $isSelected
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(info.worktree.branchName ?? "Detached HEAD")
                    .font(MacChromeTypography.body)
                Text(info.worktree.path)
                    .font(MacChromeTypography.monospacedCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Clean and eligible for safe removal.")
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CleanupStatusBadgeView(status: info.status)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(MacChromePalette.selectedFill())
        .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(info.worktree.branchName ?? "Detached HEAD"), \(info.worktree.path), eligible for worktree removal"
        )
    }
}

struct CleanupWorktreeListView: View {
    let snapshot: GitWorktreeSnapshot?
    let query: String
    @Binding var selectedIDs: Set<String>
    let onReveal: (String) -> Void
    let onCopyPath: (String) -> Void

    private var filteredWorktrees: [GitWorktreeCleanupInfo] {
        guard let snapshot else { return [] }
        return snapshot.worktrees.filter { info in
            query.isEmpty
                || info.worktree.path.localizedCaseInsensitiveContains(query)
                || (info.worktree.branchName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Worktrees")
                .font(MacChromeTypography.sectionLabel)
                .foregroundStyle(.secondary)
            if filteredWorktrees.isEmpty {
                Text("No worktrees match your filter.")
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredWorktrees) { info in
                    if info.status.isEligible {
                        CleanupWorktreeSelectionRowView(
                            info: info,
                            isSelected: Binding(
                                get: { selectedIDs.contains(GitCleanupTarget.worktree(info).id) },
                                set: { selected in
                                    let id = GitCleanupTarget.worktree(info).id
                                    if selected {
                                        selectedIDs.insert(id)
                                    } else {
                                        selectedIDs.remove(id)
                                    }
                                }
                            )
                        )
                    } else {
                        WorktreeManagementRowView(
                            info: info,
                            onReveal: { onReveal(info.worktree.path) },
                            onCopyPath: { onCopyPath(info.worktree.path) }
                        )
                    }
                }
            }
        }
    }
}

#Preview("Cleanup Worktree Selection") {
    CleanupWorktreeSelectionRowView(
        info: GitWorktreeCleanupInfo(
            worktree: GitWorktreeInfo(
                path: "/Users/example/feature-ui",
                headHash: "1234567890",
                branchName: "feature/ui",
                workingTreeState: .clean
            ),
            status: .eligible
        ),
        isSelected: .constant(true)
    )
    .padding()
    .frame(width: 560)
}
