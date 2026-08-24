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

    var id: String {
        "\(isRemote ? "remote" : "local")/\(name)"
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

    var isEligible: Bool {
        !reference.isRemote && status.isEligible
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

struct GitCleanupUnit: Identifiable, Hashable {
    let repositoryIdentity: String
    let branch: GitBranchCleanupInfo
    let worktree: GitWorktreeCleanupInfo?

    var id: String {
        let path = worktree.map { GitRepositoryContext.normalizedPath($0.worktree.path) } ?? "branch"
        return "\(repositoryIdentity)/\(branch.reference.name)/\(path)"
    }

    var isPaired: Bool {
        worktree != nil
    }

    var title: String {
        if let worktree {
            return "Branch \(branch.reference.name) and worktree \(worktree.worktree.path)"
        }
        return "Local branch \(branch.reference.name)"
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
                worktree: linkedWorktree ?? worktreeByBranch[branch.reference.name]
            )
        }
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

    init(
        repositoryPath: String,
        defaultBranchName: String,
        defaultBranchRef: String,
        analysisDescription: String,
        worktrees: [GitWorktreeCleanupInfo],
        branches: [GitBranchCleanupInfo],
        repositoryIdentity: String? = nil,
        protectedWorktreePaths: Set<String> = [],
        cleanupUnits: [GitCleanupUnit]? = nil
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
    }

    var branchCandidateCount: Int {
        cleanupUnits.count
    }

    var worktreeCandidateCount: Int {
        cleanupUnits.filter(\.isPaired).count
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
            "Remote branch origin/\(info.reference.name)"
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
        target = unit.worktree.map(GitCleanupTarget.worktree) ?? .localBranch(unit.branch)
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
