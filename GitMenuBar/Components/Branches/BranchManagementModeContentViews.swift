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
                return info.worktree.path.localizedStandardContains(query)
                    || (info.worktree.branchName?.localizedStandardContains(query) ?? false)
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
