import SwiftUI

#Preview("No Selection") {
    MainMenuPreviewHarness {
        InspectorDetailView(
            projectName: "GitMenuBar",
            selection: nil,
            overview: .empty,
            onManageBranches: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

#Preview("Stashes") {
    MainMenuPreviewHarness {
        InspectorDetailView(
            projectName: "GitMenuBar",
            selection: .stashes,
            overview: .empty,
            onManageBranches: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

#Preview("Branches") {
    MainMenuPreviewHarness {
        InspectorDetailView(
            projectName: "GitMenuBar",
            selection: .branches,
            overview: .empty,
            onManageBranches: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 420)
}
