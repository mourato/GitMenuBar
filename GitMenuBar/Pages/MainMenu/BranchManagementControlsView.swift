import SwiftUI

struct BranchManagementControlsView: View {
    let currentBranch: String
    let availableBranches: [String]
    let commitCount: Int
    let isRemoteAhead: Bool
    let behindCount: Int
    let isDetachedHead: Bool
    let canShowAtomicCommits: Bool
    let onBranchTap: () -> Void
    let onSelectBranch: (String) -> Void
    let onMergeBranch: (String) -> Void
    let onCreateBranchFromDetached: () -> Void
    let onQuickPull: () -> Void
    let onDeleteBranch: (String) -> Void
    let onRenameBranch: (String) -> Void
    let onMergeToDefaultBranch: ((String) -> Void)?
    let onNewBranch: () -> Void
    let onAtomicCommits: () -> Void
    let onManage: () -> Void
    let onSettings: () -> Void

    @Binding var showBranchSelector: Bool

    var body: some View {
        HStack {
            BottomBranchSelectorView(
                currentBranch: currentBranch,
                commitCount: commitCount,
                isRemoteAhead: isRemoteAhead,
                behindCount: behindCount,
                isDetachedHead: isDetachedHead,
                onTap: onBranchTap
            )
            .popover(isPresented: $showBranchSelector) {
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

            Spacer()

            if canShowAtomicCommits {
                Button("Atomic Commits") {
                    onAtomicCommits()
                }
                .buttonStyle(.borderless)
                .font(MacChromeTypography.detail)
            }

            Button("Manage…") {
                onManage()
            }
            .buttonStyle(.borderless)
            .font(MacChromeTypography.detail)

            Button("Settings") {
                onSettings()
            }
            .buttonStyle(.borderless)
            .font(MacChromeTypography.detail)
        }
    }
}

#Preview("Branch Management Controls") {
    BranchManagementControlsView(
        currentBranch: "main",
        availableBranches: ["main", "feature/ui", "bugfix/sync"],
        commitCount: 3,
        isRemoteAhead: true,
        behindCount: 1,
        isDetachedHead: false,
        canShowAtomicCommits: true,
        onBranchTap: {},
        onSelectBranch: { _ in },
        onMergeBranch: { _ in },
        onCreateBranchFromDetached: {},
        onQuickPull: {},
        onDeleteBranch: { _ in },
        onRenameBranch: { _ in },
        onMergeToDefaultBranch: { _ in },
        onNewBranch: {},
        onAtomicCommits: {},
        onManage: {},
        onSettings: {},
        showBranchSelector: .constant(false)
    )
    .padding()
    .frame(width: 380)
}
