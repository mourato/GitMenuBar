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

enum GitHubStatusUnavailableReason: Equatable, Sendable {
    case gitHubCLIMissing
    case notGitHubRemote
    case commandFailed
}

/// One GitHub open total as a sidebar badge can state it. A known zero stays a
/// zero; a total nobody read yet never prints as one.
enum GitHubOpenCountBadge: Equatable, Sendable {
    case known(Int)
    case pending
    case unavailable

    /// Visible badge text. Unknown totals keep a neutral dash.
    var text: String {
        switch self {
        case let .known(count): count.formatted(.number.notation(.compactName))
        case .pending, .unavailable: "—"
        }
    }

    /// One phrase per total so VoiceOver announces issues and pull requests
    /// separately instead of as a combined count.
    func accessibilityDescription(singularNoun: String) -> String {
        switch self {
        case let .known(count):
            "\(count) open \(count == 1 ? singularNoun : "\(singularNoun)s")"
        case .pending:
            "\(Self.sentenceStart(singularNoun)) count loading"
        case .unavailable:
            "\(Self.sentenceStart(singularNoun)) count unavailable"
        }
    }

    private static func sentenceStart(_ noun: String) -> String {
        noun.prefix(1).uppercased() + noun.dropFirst()
    }
}

struct GitHubProjectStatus: Equatable, Sendable {
    let pullRequests: [GitHubPullRequestSummary]
    let openPullRequestCount: Int?
    let openIssueCount: Int?
    let unavailableReason: GitHubStatusUnavailableReason?

    static let empty = GitHubProjectStatus(
        pullRequests: [],
        openPullRequestCount: nil,
        openIssueCount: nil,
        unavailableReason: nil
    )

    /// Non-GitHub remotes show no badge: there is no open total to compare.
    /// Totals come only from the counts read, never from the limited PR list.
    var openIssueBadge: GitHubOpenCountBadge? {
        badge(for: openIssueCount)
    }

    var openPullRequestBadge: GitHubOpenCountBadge? {
        badge(for: openPullRequestCount)
    }

    private func badge(for count: Int?) -> GitHubOpenCountBadge? {
        guard unavailableReason != .notGitHubRemote else { return nil }
        guard let count else {
            return unavailableReason == nil ? .pending : .unavailable
        }
        return .known(count)
    }
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
    let gitHubStatus: GitHubProjectStatus

    static let staleThreshold: TimeInterval = 14 * 24 * 60 * 60

    var id: String {
        project.path
    }

    var pullRequests: [GitHubPullRequestSummary] {
        gitHubStatus.pullRequests
    }

    var openPullRequestCount: Int? {
        gitHubStatus.openPullRequestCount
    }

    var openIssueCount: Int? {
        gitHubStatus.openIssueCount
    }

    /// Sidebar badge state for the repository's open totals.
    /// A failed refresh keeps the last GitHub status, so its totals are not
    /// current and show as unavailable instead of as fresh readings.
    var openIssueBadge: GitHubOpenCountBadge? {
        lastErrorDescription == nil
            ? gitHubStatus.openIssueBadge
            : gitHubStatus.openIssueBadge.map { _ in .unavailable }
    }

    var openPullRequestBadge: GitHubOpenCountBadge? {
        lastErrorDescription == nil
            ? gitHubStatus.openPullRequestBadge
            : gitHubStatus.openPullRequestBadge.map { _ in .unavailable }
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
            && gitHubStatus == other.gitHubStatus
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
