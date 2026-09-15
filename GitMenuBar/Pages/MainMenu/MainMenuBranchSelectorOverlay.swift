import SwiftUI

struct MainMenuBranchSelectorOverlay: View {
    let isDetachedHead: Bool
    let isRemoteAhead: Bool
    let behindCount: Int
    let availableBranches: [String]
    let currentBranch: String
    let onCreateBranchFromDetached: () -> Void
    let onQuickPull: () -> Void
    let onSelectBranch: (String) -> Void
    let onMergeBranch: (String) -> Void
    let onDeleteBranch: (String) -> Void
    let onRenameBranch: (String) -> Void
    let onMergeToDefaultBranch: (String) -> Void
    let onNewBranch: () -> Void

    var body: some View {
        BranchSelectorPopoverView(
            isDetachedHead: isDetachedHead,
            isRemoteAhead: isRemoteAhead,
            behindCount: behindCount,
            availableBranches: availableBranches,
            currentBranch: currentBranch,
            onCreateBranchFromDetached: onCreateBranchFromDetached,
            onQuickPull: onQuickPull,
            onSelectBranch: onSelectBranch,
            onMergeBranch: onMergeBranch,
            onDeleteBranch: onDeleteBranch,
            onRenameBranch: onRenameBranch,
            onMergeToDefaultBranch: onMergeToDefaultBranch,
            onNewBranch: onNewBranch
        )
    }
}
