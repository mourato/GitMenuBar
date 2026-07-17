import Foundation

extension CleanupManagementContentView {
    func cleanupAccessibilityLabel(for info: GitBranchCleanupInfo) -> String {
        let reason: String
        switch info.status {
        case .mergedIntoDefault:
            reason = "merged into the default branch"
        case .notMerged:
            reason = "not merged into the default branch"
        case .protected:
            reason = "protected branch"
        case .current:
            reason = "current branch"
        case let .checkedOutElsewhere(path):
            reason = "checked out elsewhere at \(path)"
        case let .unknown(reason: value):
            reason = "unknown status: \(value)"
        }
        return "\(info.reference.name), \(reason), \(info.isEligible ? "eligible for cleanup" : "cleanup unavailable")"
    }

    func statusDetail(for status: GitBranchCleanupStatus) -> String? {
        switch status {
        case .mergedIntoDefault:
            return "Tip is reachable from the default branch."
        case .notMerged:
            return "Tip is not reachable from the default branch."
        case .protected:
            return "Protected branch cannot be cleaned up."
        case .current:
            return "Current branch cannot be cleaned up."
        case .checkedOutElsewhere:
            return nil
        case let .unknown(reason):
            return "Status unavailable: \(reason)"
        }
    }
}
