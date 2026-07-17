//
//  WorktreeCleanupModels.swift
//  GitMenuBar
//

import Foundation

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

struct GitWorktreeSnapshot: Hashable {
    let repositoryPath: String
    let defaultBranchName: String
    let defaultBranchRef: String
    let analysisDescription: String
    let worktrees: [GitWorktreeCleanupInfo]
    let branches: [GitBranchCleanupInfo]
}

enum GitCleanupTarget: Hashable, Identifiable {
    case localBranch(GitBranchCleanupInfo)
    case worktree(GitWorktreeCleanupInfo)
    case remoteBranch(GitBranchCleanupInfo)

    var id: String {
        switch self {
        case let .localBranch(info):
            return "local-branch/\(info.id)"
        case let .worktree(info):
            return "worktree/\(info.id)"
        case let .remoteBranch(info):
            return "remote-branch/\(info.id)"
        }
    }

    var title: String {
        switch self {
        case let .localBranch(info):
            return "Local branch \(info.reference.name)"
        case let .worktree(info):
            return "Worktree \(info.worktree.path)"
        case let .remoteBranch(info):
            return "Remote branch origin/\(info.reference.name)"
        }
    }
}

enum GitCleanupItemResultStatus: Hashable {
    case succeeded
    case skipped(reason: String)
    case failed(reason: String)

    var isSuccess: Bool {
        self == .succeeded
    }
}

struct GitCleanupItemResult: Identifiable, Hashable {
    let target: GitCleanupTarget
    let status: GitCleanupItemResultStatus

    var id: String {
        target.id
    }
}

struct GitCleanupBatchResult: Hashable {
    let items: [GitCleanupItemResult]

    var succeededCount: Int {
        items.filter { $0.status.isSuccess }.count
    }

    var skippedCount: Int {
        items.filter {
            if case .skipped = $0.status {
                return true
            } else {
                return false
            }
        }.count
    }

    var failedCount: Int {
        items.filter {
            if case .failed = $0.status {
                return true
            } else {
                return false
            }
        }.count
    }
}
