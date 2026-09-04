import SwiftUI

#Preview("No Selection") {
    MainMenuPreviewHarness {
        MainMenuInspectorPreviewHost(selection: nil)
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

#Preview("Working Tree") {
    MainMenuPreviewHarness {
        MainMenuInspectorPreviewHost(selection: .workingTree)
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 640)
}

#Preview("Stashes") {
    MainMenuPreviewHarness {
        MainMenuInspectorPreviewHost(selection: .stashes)
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

#Preview("History") {
    MainMenuPreviewHarness {
        MainMenuInspectorPreviewHost(selection: .history)
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 420)
}

private struct MainMenuInspectorPreviewHost: View {
    let selection: MainMenuInspectorSelection?
    @Namespace private var animationNamespace
    @State private var commitMessage = ""
    @FocusState private var isCommitFieldFocused: Bool

    var body: some View {
        MainMenuInspectorView(
            projectName: "GitMenuBar",
            selection: selection,
            overview: .empty,
            historySections: [],
            historySelectedItemID: nil,
            isHistoryLoading: false,
            canLoadMoreHistory: false,
            animationNamespace: animationNamespace,
            isCommitInFuture: { _ in false },
            commitMessage: $commitMessage,
            commitFieldFocus: $isCommitFieldFocused,
            showsCommitField: true,
            commitPrimaryButtonSystemImage: "checkmark",
            isCommitActionBusy: false,
            commitAutomaticMessageHint: nil,
            commitGenerationDisabledReason: nil,
            commitGenerationError: nil,
            commitAutomaticRetryAvailable: false,
            isCommitFallbackModelAvailable: false,
            commitPrimaryButtonTitle: "Commit",
            isCommitPrimaryButtonDisabled: false,
            canShowSplitCommits: true,
            workspaceSelectedFileID: nil,
            commitFocusToken: 0,
            onCommitPrimaryAction: {},
            onSplitCommits: {},
            onRetryCommitGeneration: {},
            onUseCommitFallbackModel: {},
            onCommitDidCommit: {},
            onRequestCommitFocus: {},
            onSelectWorkspaceFile: { _ in },
            onDiscardAllUnstaged: {},
            onManageBranches: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in },
            onSelectHistoryRow: { _ in },
            onOpenHistoryCommit: { _ in },
            onBackToHistory: {},
            onEditCommitMessage: { _ in },
            onGenerateCommitMessage: { _ in },
            onLoadMoreHistory: {}
        )
    }
}
