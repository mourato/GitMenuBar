import SwiftUI

struct BranchManagementControlsView: View {
    let currentBranch: String
    let commitCount: Int
    let isRemoteAhead: Bool
    let behindCount: Int
    let isDetachedHead: Bool
    let canShowAtomicCommits: Bool
    let onBranchTap: () -> Void
    let onNewBranch: () -> Void
    let onAtomicCommits: () -> Void
    let onManage: () -> Void

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

            Spacer()

            if canShowAtomicCommits {
                Button("Atomic Commits") {
                    onAtomicCommits()
                }
                .workbenchGhost()
            }

            Button("Manage") {
                onManage()
            }
            .workbenchGhost()
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
        canShowAtomicCommits: true,
        onBranchTap: {},
        onNewBranch: {},
        onAtomicCommits: {},
        onManage: {}
    )
    .padding()
    .frame(width: 380)
}
