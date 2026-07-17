import SwiftUI

struct WorktreeManagementRowView: View {
    let info: GitWorktreeCleanupInfo
    let onReveal: () -> Void
    let onCopyPath: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: info.worktree.isDetached ? "rectangle.dashed" : "folder.fill")
                .font(MacChromeTypography.body)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(info.worktree.branchName ?? "Detached HEAD")
                        .font(MacChromeTypography.body)
                        .lineLimit(1)
                    Text(shortHash)
                        .font(MacChromeTypography.monospacedCaption)
                        .foregroundStyle(.secondary)
                }

                Text(info.worktree.path)
                    .font(MacChromeTypography.monospacedCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if let statusDetail {
                    Text(statusDetail)
                        .font(MacChromeTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    CleanupStatusBadgeView(status: info.status)
                    if info.worktree.workingTreeState == .clean {
                        Label("Clean", systemImage: "checkmark")
                            .font(MacChromeTypography.caption)
                            .foregroundStyle(.secondary)
                    } else if info.worktree.workingTreeState == .dirty {
                        Label("Uncommitted changes", systemImage: "pencil")
                            .font(MacChromeTypography.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 4)

            Menu {
                Button("Reveal in Finder", action: onReveal)
                Button("Copy Path", action: onCopyPath)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(MacChromeTypography.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .opacity(isHovered ? 1 : 0.4)
            .accessibilityLabel("Actions for \(info.worktree.branchName ?? "detached worktree")")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .background(isHovered ? MacChromePalette.hoverFill() : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
        .onHover { inside in
            isHovered = inside
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Use the actions menu to reveal or copy this path. Removal is unavailable in this version.")
    }

    private var shortHash: String {
        String(info.worktree.headHash.prefix(8))
    }

    private var accessibilityLabel: String {
        let branch = info.worktree.branchName ?? "detached HEAD"
        return "\(branch), \(info.worktree.path), \(statusDescription)"
    }

    private var statusDescription: String {
        switch info.status {
        case .eligible:
            return "eligible for cleanup"
        case .main:
            return "main worktree"
        case .current:
            return "current worktree"
        case .dirty:
            return "has uncommitted changes"
        case let .locked(reason):
            return "locked: \(reason)"
        case let .prunable(reason):
            return "prunable: \(reason)"
        case .branchNotMerged:
            return "branch is not merged"
        case .detached:
            return "detached"
        case let .unknown(reason):
            return "unknown: \(reason)"
        }
    }

    private var statusDetail: String? {
        switch info.status {
        case .eligible:
            return "Ready for cleanup."
        case .main, .current:
            return nil
        case .dirty:
            return "Uncommitted changes prevent cleanup."
        case let .locked(reason):
            return "Locked: \(reason)"
        case let .prunable(reason):
            return "Prunable: \(reason)"
        case .branchNotMerged:
            return "Branch is not merged into the default branch."
        case .detached:
            return "No branch is attached."
        case let .unknown(reason):
            return "Status unavailable: \(reason)"
        }
    }
}

#Preview("Worktree Management Rows") {
    VStack(spacing: 4) {
        WorktreeManagementRowView(
            info: GitWorktreeCleanupInfo(
                worktree: GitWorktreeInfo(
                    path: "/Users/example/feature-ui",
                    headHash: "1234567890abcdef",
                    branchName: "feature/ui",
                    workingTreeState: .clean
                ),
                status: .eligible
            ),
            onReveal: {},
            onCopyPath: {}
        )
        WorktreeManagementRowView(
            info: GitWorktreeCleanupInfo(
                worktree: GitWorktreeInfo(
                    path: "/Users/example/dirty",
                    headHash: "abcdef1234567890",
                    branchName: "feature/dirty",
                    workingTreeState: .dirty
                ),
                status: .dirty
            ),
            onReveal: {},
            onCopyPath: {}
        )
    }
    .padding()
    .frame(width: 560)
}
