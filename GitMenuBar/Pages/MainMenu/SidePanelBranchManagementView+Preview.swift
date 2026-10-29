import SwiftUI

#Preview("Side Panel Branch Management") {
    MainMenuPreviewHarness {
        SidePanelBranchManagementView(
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in },
            onCreateBranch: {},
            onRenameBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 640)
}
