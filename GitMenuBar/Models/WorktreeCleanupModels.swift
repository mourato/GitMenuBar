//
//  WorktreeCleanupModels.swift
//  GitMenuBar
//

import Foundation

struct GitCleanupProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let projectName: String?
    let detail: String

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return min(Double(completed) / Double(total), 1)
    }
}

struct GitBranchReference: Identifiable, Hashable {
    let name: String
    let headHash: String
    let isRemote: Bool
    let remoteName: String?

    init(name: String, headHash: String, isRemote: Bool, remoteName: String? = nil) {
        self.name = name
        self.headHash = headHash
        self.isRemote = isRemote
        self.remoteName = remoteName
    }

    var id: String {
        guard isRemote else { return "local/\(name)" }
        if let remoteName, remoteName != "origin" {
            return "remote/\(remoteName)/\(name)"
        }
        return "remote/\(name)"
    }

    var qualifiedName: String {
        isRemote ? "\(remoteName ?? "origin")/\(name)" : name
    }
}

enum GitBranchCleanupStatus: Hashable {
    case mergedIntoDefault
    case notMerged
    case protected
    case current
    case checkedOutElsewhere(path: String)
    case unknown(reason: String)

    var isEligible: Bool {
        self == .mergedIntoDefault
    }

    var isCheckedOutElsewhere: Bool {
        if case .checkedOutElsewhere = self {
            return true
        }
        return false
    }
}

struct GitBranchCleanupInfo: Identifiable, Hashable {
    let reference: GitBranchReference
    let status: GitBranchCleanupStatus
    let worktreePath: String?
    let isMergedIntoDefaultHint: Bool?

    init(
        reference: GitBranchReference,
        status: GitBranchCleanupStatus,
        worktreePath: String?,
        isMergedIntoDefaultHint: Bool? = nil
    ) {
        self.reference = reference
        self.status = status
        self.worktreePath = worktreePath
        self.isMergedIntoDefaultHint = isMergedIntoDefaultHint
    }

    var isEligible: Bool {
        !reference.isRemote && status.isEligible
    }

    var isMergedIntoDefault: Bool {
        isMergedIntoDefaultHint ?? (status == .mergedIntoDefault)
    }

    var id: String {
        reference.id
    }
}

enum GitWorktreeCleanupStatus: Hashable {
    case eligible
    case main
    case current
    case dirty
    case locked(reason: String)
    case prunable(reason: String)
    case branchNotMerged
    case detached
    case unknown(reason: String)

    var isEligible: Bool {
        self == .eligible
    }
}

struct GitWorktreeCleanupInfo: Identifiable, Hashable {
    let worktree: GitWorktreeInfo
    let status: GitWorktreeCleanupStatus

    var id: String {
        worktree.id
    }
}

enum GitCleanupUnitMode: Hashable {
    case safe
    case deleteBranch
    case removeWorktree
    case forceRemoveWorktree

    var id: String {
        switch self {
        case .safe:
            "safe"
        case .deleteBranch:
            "delete-branch"
        case .removeWorktree:
            "remove-worktree"
        case .forceRemoveWorktree:
            "force-worktree"
        }
    }
}

struct GitCleanupUnit: Identifiable, Hashable {
    let repositoryIdentity: String
    let branch: GitBranchCleanupInfo
    let worktree: GitWorktreeCleanupInfo?
    let mode: GitCleanupUnitMode

    init(
        repositoryIdentity: String,
        branch: GitBranchCleanupInfo,
        worktree: GitWorktreeCleanupInfo?,
        mode: GitCleanupUnitMode = .safe
    ) {
        self.repositoryIdentity = repositoryIdentity
        self.branch = branch
        self.worktree = worktree
        self.mode = mode
    }

    var id: String {
        let path = worktree.map { GitRepositoryContext.normalizedPath($0.worktree.path) } ?? "branch"
        let prefix = mode == .safe ? "" : "\(mode.id)/"
        return "\(prefix)\(repositoryIdentity)/\(branch.reference.name)/\(path)"
    }

    var isPaired: Bool {
        worktree?.worktree.branchName != nil && !isWorktreeOnlyAction
    }

    var isForceWorktreeRemoval: Bool {
        mode == .forceRemoveWorktree
    }

    var isBranchOnlyAction: Bool {
        mode == .deleteBranch
    }

    var isWorktreeOnlyAction: Bool {
        mode == .removeWorktree || mode == .forceRemoveWorktree
    }

    var isDangerousBranchDeletion: Bool {
        !isWorktreeOnlyAction && !branch.isMergedIntoDefault
    }

    var canPrimaryClean: Bool {
        guard !branch.reference.isRemote,
              branch.status != .protected,
              branch.status != .current else { return false }
        if isBranchOnlyAction {
            return worktree == nil
        }
        if isWorktreeOnlyAction {
            return worktree?.status == .eligible
                || worktree?.status == .branchNotMerged
                || worktree?.status == .detached
        }
        if let worktree {
            return worktree.status == .eligible || worktree.status == .branchNotMerged
        }
        return branch.status == .mergedIntoDefault || branch.status == .notMerged
    }

    var title: String {
        if isForceWorktreeRemoval, let worktree {
            return "Worktree \(worktree.worktree.path) (branch kept)"
        }
        if isWorktreeOnlyAction, let worktree {
            return "Worktree \(worktree.worktree.path) (branch kept)"
        }
        if isBranchOnlyAction {
            return "Local branch \(branch.reference.name)"
        }
        if let worktree {
            return "Branch \(branch.reference.name) and worktree \(worktree.worktree.path)"
        }
        return "Local branch \(branch.reference.name)"
    }

    static func forceWorktreeRemoval(
        repositoryIdentity: String,
        info: GitWorktreeCleanupInfo
    ) -> GitCleanupUnit {
        let branchName = info.worktree.branchName ?? "detached"
        let branch = GitBranchCleanupInfo(
            reference: GitBranchReference(
                name: branchName,
                headHash: info.worktree.headHash,
                isRemote: false
            ),
            status: .notMerged,
            worktreePath: info.worktree.path
        )
        return GitCleanupUnit(
            repositoryIdentity: repositoryIdentity,
            branch: branch,
            worktree: info,
            mode: .forceRemoveWorktree
        )
    }

    func deletingBranchOnly() -> GitCleanupUnit {
        GitCleanupUnit(
            repositoryIdentity: repositoryIdentity,
            branch: branch,
            worktree: worktree,
            mode: .deleteBranch
        )
    }

    func removingWorktreeOnly() -> GitCleanupUnit? {
        guard worktree != nil else { return nil }
        return GitCleanupUnit(
            repositoryIdentity: repositoryIdentity,
            branch: branch,
            worktree: worktree,
            mode: .removeWorktree
        )
    }

    static func build(
        repositoryIdentity: String,
        branches: [GitBranchCleanupInfo],
        worktrees: [GitWorktreeCleanupInfo]
    ) -> [GitCleanupUnit] {
        let worktreeByBranch: [String: GitWorktreeCleanupInfo] = Dictionary(
            worktrees.compactMap { info in
                guard info.status.isEligible, let branchName = info.worktree.branchName else { return nil }
                return (branchName, info)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return branches.compactMap { branch in
            guard !branch.reference.isRemote else { return nil }
            let linkedWorktree: GitWorktreeCleanupInfo?
            switch branch.status {
            case .mergedIntoDefault:
                linkedWorktree = nil
            case let .checkedOutElsewhere(path):
                linkedWorktree = worktrees.first {
                    $0.status.isEligible
                        && $0.worktree.branchName == branch.reference.name
                        && GitRepositoryContext.normalizedPath($0.worktree.path)
                        == GitRepositoryContext.normalizedPath(path)
                }
                guard linkedWorktree != nil else { return nil }
            default:
                return nil
            }
            return GitCleanupUnit(
                repositoryIdentity: repositoryIdentity,
                branch: branch,
                worktree: linkedWorktree ?? worktreeByBranch[branch.reference.name],
                mode: .safe
            )
        }
    }

    static func buildManagementUnits(
        repositoryIdentity: String,
        branches: [GitBranchCleanupInfo],
        worktrees: [GitWorktreeCleanupInfo]
    ) -> [GitCleanupUnit] {
        let localBranches = branches.filter { !$0.reference.isRemote }
        let worktreeByBranch = Dictionary(
            worktrees.compactMap { info -> (String, GitWorktreeCleanupInfo)? in
                guard let branchName = info.worktree.branchName else { return nil }
                return (branchName, info)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var units = localBranches.map { branch in
            GitCleanupUnit(
                repositoryIdentity: repositoryIdentity,
                branch: branch,
                worktree: worktreeByBranch[branch.reference.name]
            )
        }

        let localBranchNames = Set(localBranches.map(\.reference.name))
        for worktree in worktrees where worktree.worktree.branchName.map({ !localBranchNames.contains($0) }) ?? true {
            let name = worktree.worktree.branchName ?? "detached"
            let branch = GitBranchCleanupInfo(
                reference: GitBranchReference(name: name, headHash: worktree.worktree.headHash, isRemote: false),
                status: .notMerged,
                worktreePath: worktree.worktree.path
            )
            units.append(
                GitCleanupUnit(
                    repositoryIdentity: repositoryIdentity,
                    branch: branch,
                    worktree: worktree,
                    mode: .removeWorktree
                )
            )
        }
        return units
    }
}

struct GitWorktreeSnapshot: Hashable {
    let repositoryPath: String
    let defaultBranchName: String
    let defaultBranchRef: String
    let analysisDescription: String
    let worktrees: [GitWorktreeCleanupInfo]
    let branches: [GitBranchCleanupInfo]
    let repositoryIdentity: String
    let protectedWorktreePaths: Set<String>
    let cleanupUnits: [GitCleanupUnit]
    let managementUnits: [GitCleanupUnit]

    init(
        repositoryPath: String,
        defaultBranchName: String,
        defaultBranchRef: String,
        analysisDescription: String,
        worktrees: [GitWorktreeCleanupInfo],
        branches: [GitBranchCleanupInfo],
        repositoryIdentity: String? = nil,
        protectedWorktreePaths: Set<String> = [],
        cleanupUnits: [GitCleanupUnit]? = nil,
        managementUnits: [GitCleanupUnit]? = nil
    ) {
        self.repositoryPath = repositoryPath
        self.defaultBranchName = defaultBranchName
        self.defaultBranchRef = defaultBranchRef
        self.analysisDescription = analysisDescription
        self.worktrees = worktrees
        self.branches = branches
        self.repositoryIdentity = repositoryIdentity ?? GitRepositoryContext.normalizedPath(repositoryPath)
        self.protectedWorktreePaths = Set(protectedWorktreePaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
        self.cleanupUnits = cleanupUnits ?? GitCleanupUnit.build(
            repositoryIdentity: self.repositoryIdentity,
            branches: branches,
            worktrees: worktrees
        )
        self.managementUnits = managementUnits ?? GitCleanupUnit.buildManagementUnits(
            repositoryIdentity: self.repositoryIdentity,
            branches: branches,
            worktrees: worktrees
        )
    }

    var branchCandidateCount: Int {
        cleanupUnits.count
    }

    var worktreeCandidateCount: Int {
        cleanupUnits.filter(\.isPaired).count
    }

    func canForceRemove(_ info: GitWorktreeCleanupInfo) -> Bool {
        let path = GitRepositoryContext.normalizedPath(info.worktree.path)
        return info.status == .dirty
            && info.worktree.branchName != nil
            && !info.worktree.isMainWorktree
            && path != GitRepositoryContext.normalizedPath(repositoryPath)
            && !protectedWorktreePaths.contains(path)
    }
}

enum GitCleanupTarget: Hashable, Identifiable {
    case localBranch(GitBranchCleanupInfo)
    case worktree(GitWorktreeCleanupInfo)
    case remoteBranch(GitBranchCleanupInfo)

    var id: String {
        switch self {
        case let .localBranch(info):
            "local-branch/\(info.id)"
        case let .worktree(info):
            "worktree/\(info.id)"
        case let .remoteBranch(info):
            "remote-branch/\(info.id)"
        }
    }

    var title: String {
        switch self {
        case let .localBranch(info):
            "Local branch \(info.reference.name)"
        case let .worktree(info):
            "Worktree \(info.worktree.path)"
        case let .remoteBranch(info):
            "Remote branch \(info.reference.qualifiedName)"
        }
    }
}

enum GitCleanupItemResultStatus: Hashable {
    case succeeded
    case partiallySucceeded(reason: String)
    case skipped(reason: String)
    case failed(reason: String)

    var isSuccess: Bool {
        self == .succeeded
    }
}

struct GitCleanupItemResult: Identifiable, Hashable {
    let target: GitCleanupTarget
    let unit: GitCleanupUnit?
    let status: GitCleanupItemResultStatus

    init(target: GitCleanupTarget, status: GitCleanupItemResultStatus) {
        self.target = target
        unit = nil
        self.status = status
    }

    init(unit: GitCleanupUnit, status: GitCleanupItemResultStatus) {
        target = switch unit.mode {
        case .deleteBranch:
            .localBranch(unit.branch)
        case .removeWorktree, .forceRemoveWorktree:
            unit.worktree.map(GitCleanupTarget.worktree) ?? .localBranch(unit.branch)
        case .safe:
            unit.worktree.map(GitCleanupTarget.worktree) ?? .localBranch(unit.branch)
        }
        self.unit = unit
        self.status = status
    }

    var id: String {
        unit?.id ?? target.id
    }
}

struct GitCleanupBatchResult: Hashable {
    let items: [GitCleanupItemResult]

    var succeededCount: Int {
        items.filter(\.status.isSuccess).count
    }

    var skippedCount: Int {
        items.filter {
            if case .skipped = $0.status {
                true
            } else {
                false
            }
        }.count
    }

    var failedCount: Int {
        items.filter {
            if case .failed = $0.status {
                true
            } else {
                false
            }
        }.count
    }
}
