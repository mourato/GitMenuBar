import Foundation

struct BranchMenuRowAdapter: Identifiable, Equatable {
    let branchName: String
    let currentBranchName: String

    var id: String {
        branchName
    }

    var isCurrentBranch: Bool {
        branchName == currentBranchName
    }

    var canMerge: Bool {
        !isCurrentBranch
    }

    var canDelete: Bool {
        !isCurrentBranch
    }

    var canRename: Bool {
        true
    }
}
