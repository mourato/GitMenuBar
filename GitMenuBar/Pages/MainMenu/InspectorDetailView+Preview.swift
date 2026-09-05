import SwiftUI

#Preview("No Selection") {
    MainMenuPreviewHarness {
        InspectorDetailView(
            projectName: "GitMenuBar",
            selection: nil,
            overview: .empty,
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
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

#Preview("Push and Sync") {
    MainMenuPreviewHarness {
        InspectorDetailView(
            projectName: "GitMenuBar",
            selection: .unpushedCommits,
            overview: .empty,
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
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in }
        )
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 420)
}
