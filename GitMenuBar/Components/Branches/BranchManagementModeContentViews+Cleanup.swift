import Foundation

extension CleanupManagementContentView {
    func cleanupAccessibilityLabel(for info: GitBranchCleanupInfo) -> String {
        let reason = switch info.status {
        case .mergedIntoDefault:
            "merged into the default branch"
        case .notMerged:
            "not merged into the default branch"
        case .protected:
            "protected branch"
        case .current:
            "current branch"
        case let .checkedOutElsewhere(path):
            "checked out elsewhere at \(path)"
        case let .unknown(reason: value):
            "unknown status: \(value)"
        }
        return "\(info.reference.name), \(reason), cleanup unavailable"
    }

    func statusDetail(for status: GitBranchCleanupStatus) -> String? {
        switch status {
        case .mergedIntoDefault:
            "Tip is already in the default branch."
        case .notMerged:
            "Tip is not in the default branch yet."
        case .protected:
            "Protected branch cannot be cleaned up."
        case .current:
            "Current branch cannot be cleaned up."
        case let .checkedOutElsewhere(path):
            "Checked out in another worktree: \(path)."
        case let .unknown(reason):
            "Status unavailable: \(reason)"
        }
    }

    func worktreeStatusDetail(for status: GitWorktreeCleanupStatus) -> String {
        switch status {
        case .eligible:
            "Ready for cleanup."
        case .main:
            "Main worktree cannot be removed."
        case .current:
            "Current worktree cannot be removed."
        case .dirty:
            "Uncommitted changes prevent cleanup."
        case let .locked(reason):
            "Locked: \(reason)"
        case let .prunable(reason):
            "Prunable: \(reason)"
        case .branchNotMerged:
            "Branch is not merged into the default branch."
        case .detached:
            "No branch is attached."
        case let .unknown(reason):
            "Status unavailable: \(reason)"
        }
    }
}
