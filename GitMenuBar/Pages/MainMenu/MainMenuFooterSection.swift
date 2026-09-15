import SwiftUI

struct MainMenuFooterSection<BranchSelector: View>: View {
    let currentBranch: String
    let commitCount: Int
    let isRemoteAhead: Bool
    let behindCount: Int
    let isDetachedHead: Bool
    let onBranchTap: () -> Void
    @Binding var isBranchSelectorPresented: Bool
    @ViewBuilder let branchSelector: BranchSelector

    var body: some View {
        BranchManagementControlsView(
            currentBranch: currentBranch,
            commitCount: commitCount,
            isRemoteAhead: isRemoteAhead,
            behindCount: behindCount,
            isDetachedHead: isDetachedHead,
            isBranchSelectorPresented: isBranchSelectorPresented,
            onBranchTap: onBranchTap
        )
        .popover(isPresented: $isBranchSelectorPresented, arrowEdge: .bottom) {
            branchSelector
        }
    }
}

#Preview("Footer Section") {
    MainMenuFooterSection(
        currentBranch: "feature/slices",
        commitCount: 3,
        isRemoteAhead: false,
        behindCount: 0,
        isDetachedHead: false,
        onBranchTap: {},
        isBranchSelectorPresented: .constant(false),
        branchSelector: {
            Text("Branch selector")
                .padding()
        }
    )
    .frame(width: 380)
    .padding()
}
