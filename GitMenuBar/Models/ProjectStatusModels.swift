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

/// Projects sidebar groups, ordered by the next action the operator takes.
/// Working (a running agent) is assigned by the sidebar, not by Git state.
enum ProjectSidebarGroup: CaseIterable, Equatable {
    case working
    case needsAction
    case inReview
    case upToDate
    case unavailable

    var title: String {
        switch self {
        case .working: "Working"
        case .needsAction: "Needs Action"
        case .inReview: "In Review"
        case .upToDate: "Up to Date"
        case .unavailable: "Unavailable"
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

/// Status dot severity. A project without one shows no dot.
enum ProjectAttentionSeverity: Equatable, Hashable, Sendable {
    /// Failing checks, or the branch is behind or diverged.
    case critical
    /// Uncommitted changes or commits not yet pushed: local work at risk.
    case localWork
}

enum GitHubStatusUnavailableReason: Equatable, Sendable {
    case gitHubCLIMissing
    case notGitHubRemote
    case commandFailed
}

/// One GitHub open total as a sidebar badge can state it. Known positive totals
/// render as badges; a known zero is intentionally omitted.
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
    /// Known zero totals also show no badge. Totals come only from the counts
    /// read, never from the limited PR list.
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
        guard count > 0 else { return nil }
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
        // Stale data from a failed refresh never raises a dot.
        guard lastErrorDescription == nil else { return nil }
        if behindCount > 0 || hasFailingChecks {
            return .critical
        }
        if stagedCount > 0 || unstagedCount > 0 || aheadCount > 0 || unpushedBranchCount > 0 {
            return .localWork
        }
        return nil
    }

    /// Reads the pull-request detail list, so it sees only the listed pull
    /// requests, never the repository total.
    var hasFailingChecks: Bool {
        pullRequests.contains(where: { $0.checksState == .failing })
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

    /// Git-state group for the sidebar. Unmerged branches alone are review
    /// work, never Needs Action.
    var sidebarGroup: ProjectSidebarGroup {
        if classification == .unavailable {
            return .unavailable
        }
        switch attentionPriority {
        case .requiresAction, .updateAvailable: return .needsAction
        case .review: return .inReview
        case .clean: return .upToDate
        }
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

    /// Separates facts. Pull-request details use " · " inside one fact, so
    /// facts need a different separator to keep their boundaries visible.
    static let summaryFactSeparator = ", "

    /// Full row summary for the tooltip and VoiceOver: the branch, when it is
    /// not the default, then every fact in urgency order.
    var statusSummary: String {
        let parts = [branchSummary].compactMap(\.self) + summaryFacts
        return parts.isEmpty ? "Up to date" : parts.joined(separator: Self.summaryFactSeparator)
    }

    /// Row facts, most urgent first, so truncation never hides which fact
    /// matters. The status dot's cause always leads: failing checks,
    /// then behind or diverged, then uncommitted changes. Every Needs Action
    /// or In Review row states at least one fact, so it never reads
    /// "Up to date".
    var summaryFacts: [String] {
        guard lastErrorDescription == nil else { return ["Unavailable"] }
        var facts: [String] = []
        let failing = pullRequests.first { $0.headBranch == branchName && $0.checksState == .failing }
            ?? pullRequests.first { $0.checksState == .failing }
        if let failing {
            facts.append(Self.pullRequestSummary(failing))
        }
        if behindCount > 0, aheadCount > 0 {
            facts.append("Diverged (\(aheadCount) ahead · \(behindCount) behind)")
        } else if behindCount > 0 {
            facts.append("\(behindCount) commit\(behindCount == 1 ? "" : "s") behind")
        }
        if hasWorkingTreeChanges {
            facts.append("Uncommitted changes")
        }
        if aheadCount > 0, behindCount == 0 {
            facts.append("\(aheadCount) commit\(aheadCount == 1 ? "" : "s") to push")
        }
        if let unpushedBranchSummary {
            facts.append(unpushedBranchSummary)
        }
        if let pullRequest = currentPullRequest ?? otherPullRequest, pullRequest != failing {
            facts.append(Self.pullRequestSummary(pullRequest))
        }
        if let unmergedBranchSummary {
            facts.append(unmergedBranchSummary)
        }
        if isDetachedHead {
            facts.append("Detached")
        } else if branchName.isEmpty {
            facts.append("Unknown branch")
        }
        if isStale {
            facts.append("Stale work")
        }
        return facts
    }

    /// The current branch name for the tooltip and VoiceOver. The default
    /// branch carries no information; detached and unknown are facts.
    var branchSummary: String? {
        guard !isDetachedHead, !branchName.isEmpty, !isDefaultBranch else { return nil }
        return branchName
    }

    /// Branches with unpushed commits beyond the current branch. The current
    /// branch's own commits are already stated as commits to push.
    var unpushedBranchSummary: String? {
        let otherUnpushed = unpushedBranchCount - (aheadCount > 0 ? 1 : 0)
        guard otherUnpushed > 0 else { return nil }
        return "\(otherUnpushed) branch\(otherUnpushed == 1 ? "" : "es") with unpushed commits"
    }

    var unmergedBranchSummary: String? {
        guard unmergedBranchCount > 0 else { return nil }
        return "\(unmergedBranchCount) unmerged branch\(unmergedBranchCount == 1 ? "" : "es")"
    }

    /// The current branch's own pull request. Repository totals live in the
    /// badges, so the summary never restates them from the limited list.
    private var currentPullRequest: GitHubPullRequestSummary? {
        pullRequests.first(where: { $0.headBranch == branchName })
    }

    /// One pull request when the current branch has none: the one needing
    /// action first, so the row states a reason instead of a count.
    private var otherPullRequest: GitHubPullRequestSummary? {
        pullRequests.first(where: \.needsAction) ?? pullRequests.first
    }

    private static func pullRequestSummary(_ pullRequest: GitHubPullRequestSummary) -> String {
        "PR #\(pullRequest.number) \(pullRequest.statusSummary)"
    }
}
