import Foundation

// MARK: - Branch Filter

/// Filter options for branch list filtering chips in the Branches side panel.
enum BranchFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case mergeable
    case dirty
    case stale

    var title: String {
        switch self {
        case .all: "All"
        case .mergeable: "Mergeable"
        case .dirty: "Dirty"
        case .stale: "Stale"
        }
    }
}

// MARK: - Cleanup Badge Status

/// Status representation for branch cleanup badges.
enum BranchCleanupBadgeStatus: Hashable, Sendable {
    case merged
    case dirty
    case blocked(reason: String)

    var isMerged: Bool {
        if case .merged = self {
            return true
        }
        return false
    }

    var isDirty: Bool {
        if case .dirty = self {
            return true
        }
        return false
    }
}

// MARK: - Branch List Row

/// Model representing a single local branch row in the side panel.
struct BranchListRow: Identifiable, Hashable, Sendable {
    let branch: BranchInfo
    let cleanupStatus: BranchCleanupBadgeStatus?
    let hasWorktree: Bool

    var id: String {
        branch.id
    }

    var isMerged: Bool {
        cleanupStatus?.isMerged == true
    }

    var isDirty: Bool {
        cleanupStatus?.isDirty == true
    }
}

// MARK: - Remote Branch Group

/// Model representing a grouped collection of remote branches sharing a path segment prefix.
///
/// **Grouping Rule**:
/// Remote branches are grouped by common path segment prefix when 2 or more branches share it.
/// If all candidate branches within a group share additional path segments (e.g. `dependabot/npm_and_yarn/...`),
/// the group title includes all shared segments up to the last shared `/` directory segment before the branch leaf.
/// Singletons (only 1 branch with a given prefix) and branches without `/` remain ungrouped.
struct RemoteBranchGroup: Identifiable, Hashable, Sendable {
    let name: String
    let branches: [BranchInfo]

    var id: String {
        name
    }
}

// MARK: - Resolved Branch List Model

/// Resolved state produced by `BranchListResolver`.
struct BranchListModel: Equatable, Sendable {
    let current: BranchInfo?
    let local: [BranchListRow]
    let visible: [BranchListRow]
    let collapsedMerged: [BranchListRow]
    let remoteGroups: [RemoteBranchGroup]
    let ungroupedRemote: [BranchInfo]
    let readyCount: Int
    let blockedCount: Int
    let filterCounts: [BranchFilter: Int]

    var hasCollapsedMerged: Bool {
        !collapsedMerged.isEmpty
    }

    func count(for filter: BranchFilter) -> Int {
        filterCounts[filter] ?? 0
    }
}

// MARK: - Branch List Resolver

/// Pure resolver computing the branch list display model from branch data and worktree snapshots.
enum BranchListResolver {
    private static let staleThresholdSeconds: TimeInterval = 10 * 24 * 60 * 60

    static func resolve(
        branches: [BranchInfo],
        snapshot: GitWorktreeSnapshot? = nil,
        query: String = "",
        filter: BranchFilter = .all,
        now: Date
    ) -> BranchListModel {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentBranch = branches.first(where: \.isCurrent)

        let index = SnapshotIndex(snapshot: snapshot)
        let evaluatedLocal = evaluateLocalRows(branches: branches, query: trimmedQuery, index: index)
        let filterCounts = computeFilterCounts(rows: evaluatedLocal, now: now)
        let filteredLocal = applyFilter(filter, to: evaluatedLocal, now: now)
        let sortedLocal = sortLocalRows(filteredLocal)
        let (visible, collapsed) = partitionMergedRows(sortedLocal)

        let (remoteGroups, ungroupedRemote) = resolveRemoteSection(
            branches: branches,
            filter: filter,
            query: trimmedQuery
        )

        let (readyCount, blockedCount) = snapshot?.cleanupCounts(matching: trimmedQuery) ?? (0, 0)

        return BranchListModel(
            current: currentBranch,
            local: sortedLocal,
            visible: visible,
            collapsedMerged: collapsed,
            remoteGroups: remoteGroups,
            ungroupedRemote: ungroupedRemote,
            readyCount: readyCount,
            blockedCount: blockedCount,
            filterCounts: filterCounts
        )
    }

    private static func matchesQuery(branch: BranchInfo, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return branch.displayName.localizedStandardContains(query)
            || branch.name.localizedStandardContains(query)
    }

    static func isStale(branch: BranchInfo, now: Date) -> Bool {
        guard branch.isLocal, !branch.isCurrent, let lastCommitDate = branch.lastCommitDate else {
            return false
        }
        return now.timeIntervalSince(lastCommitDate) > staleThresholdSeconds
    }

    private static func evaluateLocalRows(
        branches: [BranchInfo],
        query: String,
        index: SnapshotIndex
    ) -> [BranchListRow] {
        branches.filter { $0.isLocal && matchesQuery(branch: $0, query: query) }.map { branch in
            let linkedWorktree = index.worktree(for: branch.name)
            let badgeStatus = determineBadgeStatus(
                branch: branch,
                linkedWorktree: linkedWorktree,
                index: index
            )
            return BranchListRow(
                branch: branch,
                cleanupStatus: badgeStatus,
                hasWorktree: linkedWorktree != nil
            )
        }
    }

    private static func determineBadgeStatus(
        branch: BranchInfo,
        linkedWorktree: GitWorktreeCleanupInfo?,
        index: SnapshotIndex
    ) -> BranchCleanupBadgeStatus? {
        if linkedWorktree?.status == .dirty {
            return .dirty
        }
        if let unit = index.unit(for: branch.name) {
            if unit.worktree?.status == .dirty {
                return .dirty
            }
            if unit.canPrimaryClean, unit.branch.isMergedIntoDefault {
                return .merged
            }
            return blockedStatus(from: unit, worktree: linkedWorktree ?? unit.worktree)
        }
        if let branchInfo = index.branchInfo(for: branch.name) {
            return blockedStatus(from: branchInfo.status)
        }
        return nil
    }

    private static func blockedStatus(
        from unit: GitCleanupUnit,
        worktree: GitWorktreeCleanupInfo?
    ) -> BranchCleanupBadgeStatus? {
        if let worktreeBlocked = blockedStatus(from: worktree?.status) {
            return worktreeBlocked
        }
        return blockedStatus(from: unit.branch.status)
    }

    private static func blockedStatus(from status: GitWorktreeCleanupStatus?) -> BranchCleanupBadgeStatus? {
        guard let status else { return nil }
        switch status {
        case .dirty:
            return .dirty
        case let .locked(reason):
            return .blocked(reason: "Locked: \(reason)")
        case .main:
            return .blocked(reason: "Main worktree")
        case .current:
            return .blocked(reason: "Current worktree")
        case let .unknown(reason):
            return .blocked(reason: reason)
        case .branchNotMerged:
            return .blocked(reason: "Not merged")
        default:
            return nil
        }
    }

    private static func blockedStatus(from status: GitBranchCleanupStatus) -> BranchCleanupBadgeStatus? {
        switch status {
        case .current:
            .blocked(reason: "Current branch")
        case .protected:
            .blocked(reason: "Protected branch")
        case .notMerged:
            nil
        case let .checkedOutElsewhere(path):
            .blocked(reason: "Checked out at \(path)")
        case let .unknown(reason):
            .blocked(reason: reason)
        case .mergedIntoDefault:
            nil
        }
    }

    private static func computeFilterCounts(
        rows: [BranchListRow],
        now: Date
    ) -> [BranchFilter: Int] {
        [
            .all: rows.count,
            .mergeable: rows.filter(\.isMerged).count,
            .dirty: rows.filter(\.isDirty).count,
            .stale: rows.filter { isStale(branch: $0.branch, now: now) }.count
        ]
    }

    private static func applyFilter(
        _ filter: BranchFilter,
        to rows: [BranchListRow],
        now: Date
    ) -> [BranchListRow] {
        switch filter {
        case .all:
            rows
        case .mergeable:
            rows.filter(\.isMerged)
        case .dirty:
            rows.filter(\.isDirty)
        case .stale:
            rows.filter { isStale(branch: $0.branch, now: now) }
        }
    }

    private static func sortLocalRows(_ rows: [BranchListRow]) -> [BranchListRow] {
        rows.sorted { lhs, rhs in
            if lhs.branch.isCurrent != rhs.branch.isCurrent {
                return lhs.branch.isCurrent
            }
            return lhs.branch.name.localizedStandardCompare(rhs.branch.name) == .orderedAscending
        }
    }

    private static func partitionMergedRows(
        _ rows: [BranchListRow]
    ) -> (visible: [BranchListRow], collapsed: [BranchListRow]) {
        var visible: [BranchListRow] = []
        var collapsed: [BranchListRow] = []
        var mergedCount = 0

        for row in rows {
            if row.isMerged {
                mergedCount += 1
                if mergedCount <= 3 {
                    visible.append(row)
                } else {
                    collapsed.append(row)
                }
            } else {
                visible.append(row)
            }
        }
        return (visible, collapsed)
    }

    private static func resolveRemoteSection(
        branches: [BranchInfo],
        filter: BranchFilter,
        query: String
    ) -> (groups: [RemoteBranchGroup], ungrouped: [BranchInfo]) {
        guard filter == .all else { return ([], []) }
        let matching = branches.filter { $0.isRemote && matchesQuery(branch: $0, query: query) }
        return resolveRemoteGroups(branches: matching)
    }

    static func resolveRemoteGroups(
        branches: [BranchInfo]
    ) -> (groups: [RemoteBranchGroup], ungrouped: [BranchInfo]) {
        var branchesWithPrefix: [String: [BranchInfo]] = [:]
        var ungrouped: [BranchInfo] = []

        for branch in branches {
            let segments = branch.name.split(separator: "/").map(String.init)
            if segments.count >= 2 {
                branchesWithPrefix[segments[0], default: []].append(branch)
            } else {
                ungrouped.append(branch)
            }
        }

        var groups: [RemoteBranchGroup] = []
        for (_, branchList) in branchesWithPrefix {
            if branchList.count < 2 {
                ungrouped.append(contentsOf: branchList)
            } else {
                let groupPrefix = longestCommonPathPrefix(branches: branchList)
                let sortedBranches = branchList.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                groups.append(RemoteBranchGroup(name: groupPrefix, branches: sortedBranches))
            }
        }

        let sortedGroups = groups.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let sortedUngrouped = ungrouped.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return (sortedGroups, sortedUngrouped)
    }

    private static func longestCommonPathPrefix(branches: [BranchInfo]) -> String {
        guard !branches.isEmpty else { return "" }
        let segmentLists = branches.map { $0.name.split(separator: "/").map(String.init) }
        let firstSegments = segmentLists[0]
        var commonSegments: [String] = []

        for segmentIndex in 0 ..< firstSegments.count {
            let candidate = firstSegments[segmentIndex]
            let allMatch = segmentLists.allSatisfy { segments in
                segmentIndex < segments.count
                    && segments[segmentIndex] == candidate
                    && segmentIndex < (segments.count - 1)
            }
            if allMatch {
                commonSegments.append(candidate)
            } else {
                break
            }
        }

        if commonSegments.isEmpty {
            return firstSegments.first ?? ""
        }
        return commonSegments.joined(separator: "/")
    }
}

// MARK: - Snapshot Index Helper

private struct SnapshotIndex {
    private let worktreesByBranch: [String: GitWorktreeCleanupInfo]
    private let cleanupUnitsByBranch: [String: GitCleanupUnit]
    private let managementUnitsByBranch: [String: GitCleanupUnit]
    private let branchesByName: [String: GitBranchCleanupInfo]

    init(snapshot: GitWorktreeSnapshot?) {
        worktreesByBranch = Dictionary(
            (snapshot?.worktrees ?? []).compactMap { info -> (String, GitWorktreeCleanupInfo)? in
                guard let branchName = info.worktree.branchName else { return nil }
                return (branchName, info)
            },
            uniquingKeysWith: { first, _ in first }
        )

        cleanupUnitsByBranch = Dictionary(
            (snapshot?.cleanupUnits ?? []).compactMap { unit -> (String, GitCleanupUnit)? in
                guard !unit.branch.reference.isRemote else { return nil }
                return (unit.branch.reference.name, unit)
            },
            uniquingKeysWith: { first, _ in first }
        )

        managementUnitsByBranch = Dictionary(
            (snapshot?.managementUnits ?? []).compactMap { unit -> (String, GitCleanupUnit)? in
                guard !unit.branch.reference.isRemote else { return nil }
                return (unit.branch.reference.name, unit)
            },
            uniquingKeysWith: { first, _ in first }
        )

        branchesByName = Dictionary(
            (snapshot?.branches ?? []).map { ($0.reference.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func worktree(for branchName: String) -> GitWorktreeCleanupInfo? {
        worktreesByBranch[branchName]
            ?? managementUnitsByBranch[branchName]?.worktree
            ?? cleanupUnitsByBranch[branchName]?.worktree
    }

    func unit(for branchName: String) -> GitCleanupUnit? {
        managementUnitsByBranch[branchName] ?? cleanupUnitsByBranch[branchName]
    }

    func branchInfo(for branchName: String) -> GitBranchCleanupInfo? {
        branchesByName[branchName]
    }
}
