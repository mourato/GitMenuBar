import SwiftUI

#Preview("Branch Management List") {
    BranchManagementListPreviewContainer()
}

private struct BranchManagementListPreviewContainer: View {
    @State private var mode = BranchManagementMode.branches
    @State private var query = ""
    @State private var selectedCleanupIDs: Set<String> = []

    var body: some View {
        BranchManagementListView(
            mode: $mode,
            query: $query,
            branchInfos: branchInfos,
            worktreeSnapshot: nil,
            worktreeErrorMessage: nil,
            selectedCleanupIDs: $selectedCleanupIDs,
            onRevealWorktree: { _ in },
            onCopyPath: { _ in },
            onDismissError: {},
            branchRow: branchRow
        )
        .frame(width: 560)
    }

    private var branchInfos: [BranchInfo] {
        [
            branch("main", isCurrent: true, trackingStatus: .upToDate, lastCommitOffset: -900),
            branch("feature/sidebar-polish", trackingStatus: .ahead(3), lastCommitOffset: -7200),
            branch("feature/remote-review", isLocal: false, isRemote: true, trackingStatus: .noRemote)
        ]
    }

    private func branchRow(_ branch: BranchInfo) -> BranchManagementRowView {
        BranchManagementRowView(
            branch: branch,
            onSwitch: {},
            onRename: {},
            onDelete: {},
            onPush: branch.isLocal ? {} : nil,
            onMerge: branch.isLocal ? {} : nil,
            onDeleteRemote: branch.isRemote ? {} : nil,
            onCheckoutLocally: branch.isRemote ? {} : nil
        )
    }

    private func branch(
        _ name: String,
        isLocal: Bool = true,
        isRemote: Bool = false,
        isCurrent: Bool = false,
        trackingStatus: BranchTrackingStatus,
        lastCommitOffset: TimeInterval = -86400
    ) -> BranchInfo {
        BranchInfo(
            name: name,
            isLocal: isLocal,
            isRemote: isRemote,
            isCurrent: isCurrent,
            trackingStatus: trackingStatus,
            lastCommitDate: Date().addingTimeInterval(lastCommitOffset)
        )
    }
}
