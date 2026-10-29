import Foundation

/// Shared one-line cleanup explanations; used by the cleanup list and the cleanup confirmation sheet.
enum CleanupDetailText {
    static func branchStatus(_ status: GitBranchCleanupStatus) -> String? {
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

    static func worktreeStatus(_ status: GitWorktreeCleanupStatus) -> String {
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
