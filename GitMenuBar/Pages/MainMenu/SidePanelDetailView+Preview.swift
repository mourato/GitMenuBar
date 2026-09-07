import SwiftUI

#Preview("Stashes") {
    MainMenuPreviewHarness {
        SidePanelDetailView(
            projectName: "GitMenuBar",
            selection: .stashes,
            overview: .empty,
            onClose: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 360)
}

#Preview("Push and Sync") {
    MainMenuPreviewHarness {
        SidePanelDetailView(
            projectName: "GitMenuBar",
            selection: .unpushedCommits,
            overview: .empty,
            onClose: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 360)
}

#Preview("Branches") {
    MainMenuPreviewHarness {
        SidePanelDetailView(
            projectName: "GitMenuBar",
            selection: .branches,
            overview: .empty,
            onClose: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 420)
}
