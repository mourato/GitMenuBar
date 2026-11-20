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
        case .inReview: "In Progress"
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

enum ProjectSummaryFact: Equatable, Sendable {
    case unavailable
    case failingPullRequest(GitHubPullRequestSummary)
    case diverged(ahead: Int, behind: Int)
    case behind(Int)
    case uncommittedChanges
    case commitsToPush(Int)
    case unpushedBranches(Int)
    case pullRequest(GitHubPullRequestSummary)
    case unmergedBranches(Int)
    case detached
    case unknownBranch
    case staleWork

    var spokenText: String {
        switch self {
        case .unavailable: "Unavailable"
        case let .failingPullRequest(pullRequest), let .pullRequest(pullRequest):
            "PR #\(pullRequest.number) \(pullRequest.statusSummary)"
        case let .diverged(ahead, behind): "Diverged (\(ahead) ahead · \(behind) behind)"
        case let .behind(count): "\(count) commit\(count == 1 ? "" : "s") behind"
        case .uncommittedChanges: "Uncommitted changes"
        case let .commitsToPush(count): "\(count) commit\(count == 1 ? "" : "s") to push"
        case let .unpushedBranches(count): "\(count) branch\(count == 1 ? "" : "es") with unpushed commits"
        case let .unmergedBranches(count): "\(count) unmerged branch\(count == 1 ? "" : "es")"
        case .detached: "Detached"
        case .unknownBranch: "Unknown branch"
        case .staleWork: "Stale work"
        }
    }

    var showsInSummaryLine: Bool {
        if case .unmergedBranches = self {
            return false
        }
        return true
    }
}

enum ProjectAttentionSeverity: Equatable, Hashable, Sendable {
    case critical
    case localWork
}

enum GitHubStatusUnavailableReason: Equatable, Sendable {
    case gitHubCLIMissing
    case notGitHubRemote
    case commandFailed
}

enum GitHubOpenCountBadge: Equatable, Sendable {
    case known(Int)
    case pending
    case unavailable

    var text: String {
        switch self {
        case let .known(count): count.formatted(.number.notation(.compactName))
        case .pending, .unavailable: "—"
        }
    }

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
    var isPrivate: Bool?

    static let empty = GitHubProjectStatus(
        pullRequests: [],
        openPullRequestCount: nil,
        openIssueCount: nil,
        unavailableReason: nil
    )

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
        guard lastErrorDescription == nil else { return nil }
        if hasFailingChecks || (behindCount > 0 && aheadCount > 0) {
            return .critical
        }
        if stagedCount > 0 || unstagedCount > 0 || aheadCount > 0 || unpushedBranchCount > 0 {
            return .localWork
        }
        return nil
    }

    var hasFailingChecks: Bool {
        pullRequests.contains(where: { $0.checksState == .failing })
    }

    var hasWorkingTreeChanges: Bool {
        stagedCount + unstagedCount + untrackedCount > 0
    }

    var isStale: Bool {
        isStale(at: Date())
    }

    func isStale(at now: Date) -> Bool {
        guard let lastActivityAt else { return false }
        return hasAttentionState && now.timeIntervalSince(lastActivityAt) >= Self.staleThreshold
    }

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

    static let summaryFactSeparator = ", "

    var statusSummary: String {
        let parts = [branchSummary].compactMap(\.self) + summaryFacts
        return parts.isEmpty ? "Up to date" : parts.joined(separator: Self.summaryFactSeparator)
    }

    var summaryFacts: [String] {
        facts.map(\.spokenText)
    }

    var visibleFacts: [ProjectSummaryFact] {
        facts.filter(\.showsInSummaryLine)
    }

    var facts: [ProjectSummaryFact] {
        guard lastErrorDescription == nil else { return [.unavailable] }
        var facts: [ProjectSummaryFact] = []
        let failing = pullRequests.first { $0.headBranch == branchName && $0.checksState == .failing }
            ?? pullRequests.first { $0.checksState == .failing }
        if let failing {
            facts.append(.failingPullRequest(failing))
        }
        if behindCount > 0, aheadCount > 0 {
            facts.append(.diverged(ahead: aheadCount, behind: behindCount))
        } else if behindCount > 0 {
            facts.append(.behind(behindCount))
        }
        if hasWorkingTreeChanges {
            facts.append(.uncommittedChanges)
        }
        if aheadCount > 0, behindCount == 0 {
            facts.append(.commitsToPush(aheadCount))
        }
        let otherUnpushed = unpushedBranchCount - (aheadCount > 0 ? 1 : 0)
        if otherUnpushed > 0 {
            facts.append(.unpushedBranches(otherUnpushed))
        }
        if let pullRequest = currentPullRequest ?? otherPullRequest, pullRequest != failing {
            facts.append(.pullRequest(pullRequest))
        }
        if unmergedBranchCount > 0 {
            facts.append(.unmergedBranches(unmergedBranchCount))
        }
        if isDetachedHead {
            facts.append(.detached)
        } else if branchName.isEmpty {
            facts.append(.unknownBranch)
        }
        if isStale {
            facts.append(.staleWork)
        }
        return facts
    }

    func idleSummary(now: Date) -> String {
        let age = lastActivityAt.map {
            min($0, now).formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        }
        let parts = [branchName.isEmpty ? nil : branchName, age].compactMap(\.self)
        return parts.isEmpty ? "Up to date" : parts.joined(separator: " · ")
    }

    var unmergedBranchBadge: Int? {
        guard lastErrorDescription == nil, unmergedBranchCount > 0 else { return nil }
        return unmergedBranchCount
    }

    var branchSummary: String? {
        guard !isDetachedHead, !branchName.isEmpty, !isDefaultBranch else { return nil }
        return branchName
    }

    private var currentPullRequest: GitHubPullRequestSummary? {
        pullRequests.first(where: { $0.headBranch == branchName })
    }

    private var otherPullRequest: GitHubPullRequestSummary? {
        pullRequests.first(where: \.needsAction) ?? pullRequests.first
    }
}
