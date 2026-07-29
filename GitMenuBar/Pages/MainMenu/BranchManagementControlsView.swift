import SwiftUI

struct BranchManagementControlsView: View {
    let currentBranch: String
    let commitCount: Int
    let isRemoteAhead: Bool
    let behindCount: Int
    let isDetachedHead: Bool
    let isBranchSelectorPresented: Bool
    let onBranchTap: () -> Void
    let onManage: () -> Void

    var body: some View {
        HStack {
            BottomBranchSelectorView(
                currentBranch: currentBranch,
                commitCount: commitCount,
                isRemoteAhead: isRemoteAhead,
                behindCount: behindCount,
                isDetachedHead: isDetachedHead,
                isPresented: isBranchSelectorPresented,
                onTap: onBranchTap
            )

            Spacer()

            Button("Branches") {
                onManage()
            }
            .workbenchGhost()
            .accessibilityHint("Shows branch and worktree management.")
            .help("Manage branches and worktrees")
        }
    }
}

#Preview("Branch Management Controls") {
    BranchManagementControlsView(
        currentBranch: "main",
        commitCount: 3,
        isRemoteAhead: true,
        behindCount: 1,
        isDetachedHead: false,
        isBranchSelectorPresented: false,
        onBranchTap: {},
        onManage: {}
    )
    .padding()
    .frame(width: 380)
}
