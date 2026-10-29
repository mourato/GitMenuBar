import Foundation

enum ProjectAttentionClassification: Equatable {
    case clean
    case needsAttention
    case unavailable
    case refreshing
}

enum ProjectAttentionPriority: Equatable {
    case requiresAction
    case review
    case updateAvailable
    case clean

    var sortOrder: Int {
        switch self {
        case .requiresAction: 0
        case .review: 1
        case .updateAvailable: 2
        case .clean: 3
        }
    }
}

enum ProjectAttentionReason: Equatable {
    case dirty
    case ahead
    case behind
    case diverged
    case noUpstream
    case branchesWithoutUpstream
    case unpushedBranches
    case unmergedBranches
    case stashes
    case openPullRequests
    case failingChecks
    case stale
    case detached
    case missing
    case invalidRepository
    case error
}

enum ProjectAttentionSeverity: Equatable, Hashable, Sendable {
    case divergedOrBehind
    case uncommittedChanges
    case unmergedOnly
}

struct ProjectStatusSnapshot: Equatable, Identifiable, Sendable {
    let project: ProjectReference
    let branchName: String
    let isDetachedHead: Bool
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let lineDiff: LineDiffStats
    let aheadCount: Int
    let behindCount: Int
    let hasUpstream: Bool
    let lastRefreshedAt: Date?
    let lastErrorDescription: String?
    let branchesWithoutUpstreamCount: Int
    let unpushedBranchCount: Int
    let unmergedBranchCount: Int
    let stashCount: Int
    let lastActivityAt: Date?
    let pullRequests: [GitHubPullRequestSummary]

    static let staleThreshold: TimeInterval = 14 * 24 * 60 * 60

    var id: String {
        project.path
    }

    func hasSameVisibleState(as other: Self) -> Bool {
        project == other.project
            && branchName == other.branchName
            && isDetachedHead == other.isDetachedHead
            && stagedCount == other.stagedCount
            && unstagedCount == other.unstagedCount
            && untrackedCount == other.untrackedCount
            && lineDiff == other.lineDiff
            && aheadCount == other.aheadCount
            && behindCount == other.behindCount
            && hasUpstream == other.hasUpstream
            && lastErrorDescription == other.lastErrorDescription
            && branchesWithoutUpstreamCount == other.branchesWithoutUpstreamCount
            && unpushedBranchCount == other.unpushedBranchCount
            && unmergedBranchCount == other.unmergedBranchCount
            && stashCount == other.stashCount
            && lastActivityAt == other.lastActivityAt
            && pullRequests == other.pullRequests
    }

    var isDefaultBranch: Bool {
        !isDetachedHead && (branchName == "main" || branchName == "master")
    }

    var severity: ProjectAttentionSeverity? {
        if behindCount > 0 {
            return .divergedOrBehind
        }
        if stagedCount > 0 || unstagedCount > 0 {
            return .uncommittedChanges
        }
        if unmergedBranchCount > 0 {
            return .unmergedOnly
        }
        return nil
    }

    var hasWorkingTreeChanges: Bool {
        stagedCount + unstagedCount + untrackedCount > 0
    }

    // ponytail: stale uses commit age; add working-tree mtimes only if this proxy proves insufficient.
    var isStale: Bool {
        isStale(at: Date())
    }

    func isStale(at now: Date) -> Bool {
        guard let lastActivityAt else { return false }
        return hasAttentionState && now.timeIntervalSince(lastActivityAt) >= Self.staleThreshold
    }

    /// Local-only branches (no upstream) and stashes are intentional in agent
    /// workflows; they do not drive project attention or sidebar state.
    private var hasAttentionState: Bool {
        hasWorkingTreeChanges || aheadCount > 0 || behindCount > 0 || isDetachedHead
            || unpushedBranchCount > 0 || unmergedBranchCount > 0
            || !pullRequests.isEmpty
    }

    var classification: ProjectAttentionClassification {
        if lastErrorDescription != nil {
            return .unavailable
        }
        if hasAttentionState {
            return .needsAttention
        }
        return .clean
    }

    var attentionPriority: ProjectAttentionPriority {
        if hasWorkingTreeChanges || aheadCount > 0 || unpushedBranchCount > 0 {
            return .requiresAction
        }
        if pullRequests.contains(where: \.needsAction) {
            return .requiresAction
        }
        if unmergedBranchCount > 0 || isDetachedHead {
            return .review
        }
        if !pullRequests.isEmpty {
            return .review
        }
        if behindCount > 0 {
            return .updateAvailable
        }
        return .clean
    }

    var reasons: Set<ProjectAttentionReason> {
        var result = Set<ProjectAttentionReason>()
        if hasWorkingTreeChanges {
            result.insert(.dirty)
        }
        if aheadCount > 0, behindCount > 0 {
            result.insert(.diverged)
        } else if aheadCount > 0 {
            result.insert(.ahead)
        } else if behindCount > 0 {
            result.insert(.behind)
        }
        if unpushedBranchCount > 0 {
            result.insert(.unpushedBranches)
        }
        if unmergedBranchCount > 0 {
            result.insert(.unmergedBranches)
        }
        if !pullRequests.isEmpty {
            result.insert(.openPullRequests)
        }
        if pullRequests.contains(where: { $0.checksState == .failing }) {
            result.insert(.failingChecks)
        }
        if isStale {
            result.insert(.stale)
        }
        if isDetachedHead {
            result.insert(.detached)
        }
        if lastErrorDescription != nil {
            result.insert(.error)
        }
        return result
    }
}
