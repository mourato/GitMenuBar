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
