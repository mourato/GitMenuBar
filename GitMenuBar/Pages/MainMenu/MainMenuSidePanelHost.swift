import SwiftUI

struct MainMenuSidePanelHost: View {
    let selection: MainMenuSidePanelSelection
    let projectName: String
    let overview: RepositoryOverviewSnapshot
    let history: SidePanelHistoryModel

    @Binding var commitMessage: String
    var commitFieldFocus: FocusState<Bool>.Binding
    let showsCommitField: Bool
    let commitPrimaryButtonSystemImage: String?
    let isCommitActionBusy: Bool
    let commitAutomaticMessageHint: String?
    let commitGenerationDisabledReason: String?
    let commitGenerationError: String?
    let commitAutomaticRetryAvailable: Bool
    let isCommitFallbackModelAvailable: Bool
    let commitPrimaryButtonTitle: String
    let isCommitPrimaryButtonDisabled: Bool
    let canShowSplitCommits: Bool
    let commitFocusToken: Int
    let workspaceSelectedFileID: MainMenuSelectableItem?

    let onClose: () -> Void
    let onCommitPrimaryAction: () -> Void
    let onSplitCommits: () -> Void
    let onRetryCommitGeneration: () -> Void
    let onUseCommitFallbackModel: () -> Void
    let onCommitDidCommit: () -> Void
    let onRequestCommitFocus: () -> Void
    let onSelectWorkspaceFile: (MainMenuSelectableItem) -> Void
    let onDiscardAllUnstaged: () -> Void
    let onRequestDiscard: (String, WorkingTreeFileStatus) -> Void
    let onRequestDeleteBranch: (String) -> Void
    let onRequestSwitchBranch: (String) -> Void
    let onCreateBranch: () -> Void
    let onRenameBranch: (String) -> Void

    var body: some View {
        switch selection {
        case .workingTree:
            SidePanelCommitWorkspaceView(
                projectName: projectName,
                commitMessage: $commitMessage,
                commitFieldFocus: commitFieldFocus,
                showsCommitField: showsCommitField,
                commitPrimaryButtonSystemImage: commitPrimaryButtonSystemImage,
                isCommitActionBusy: isCommitActionBusy,
                commitAutomaticMessageHint: commitAutomaticMessageHint,
                commitGenerationDisabledReason: commitGenerationDisabledReason,
                commitGenerationError: commitGenerationError,
                commitAutomaticRetryAvailable: commitAutomaticRetryAvailable,
                isCommitFallbackModelAvailable: isCommitFallbackModelAvailable,
                commitPrimaryButtonTitle: commitPrimaryButtonTitle,
                isCommitPrimaryButtonDisabled: isCommitPrimaryButtonDisabled,
                canShowSplitCommits: canShowSplitCommits,
                commitFocusToken: commitFocusToken,
                workspaceSelectedFileID: workspaceSelectedFileID,
                onClose: onClose,
                onCommitPrimaryAction: onCommitPrimaryAction,
                onSplitCommits: onSplitCommits,
                onRetryCommitGeneration: onRetryCommitGeneration,
                onUseCommitFallbackModel: onUseCommitFallbackModel,
                onCommitDidCommit: onCommitDidCommit,
                onRequestCommitFocus: onRequestCommitFocus,
                onSelectWorkspaceFile: onSelectWorkspaceFile,
                onDiscardAllUnstaged: onDiscardAllUnstaged,
                onRequestDiscard: onRequestDiscard
            )
        case .history, .commit:
            HistorySidePanelView(
                projectName: projectName,
                selection: selection,
                history: history,
                onClose: onClose
            )
        default:
            SidePanelDetailView(
                projectName: projectName,
                selection: selection,
                overview: overview,
                onClose: onClose,
                onRequestDiscard: onRequestDiscard,
                onRequestDeleteBranch: onRequestDeleteBranch,
                onRequestSwitchBranch: onRequestSwitchBranch,
                onCreateBranch: onCreateBranch,
                onRenameBranch: onRenameBranch
            )
        }
    }
}

#Preview("Side Panel Host") {
    SidePanelHostPreviewContent()
}

private struct SidePanelHostPreviewContent: View {
    @State private var message = ""
    @FocusState private var isFocused: Bool
    @Namespace private var namespace

    var body: some View {
        MainMenuSidePanelHost(
            selection: .workingTree,
            projectName: "Demo",
            overview: .empty,
            history: SidePanelHistoryModel(
                sections: [],
                selectedItemID: nil,
                isLoading: false,
                canLoadMore: false,
                animationNamespace: namespace,
                isCommitInFuture: { _ in false },
                onSelectRow: { _ in },
                onOpenCommit: { _ in },
                onBackToHistory: {},
                onEditCommitMessage: { _ in },
                onGenerateCommitMessage: { _ in },
                onLoadMore: {},
                onOpenLocalFile: { _ in }
            ),
            commitMessage: $message,
            commitFieldFocus: $isFocused,
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
            canShowSplitCommits: false,
            commitFocusToken: 0,
            workspaceSelectedFileID: nil,
            onClose: {},
            onCommitPrimaryAction: {},
            onSplitCommits: {},
            onRetryCommitGeneration: {},
            onUseCommitFallbackModel: {},
            onCommitDidCommit: {},
            onRequestCommitFocus: {},
            onSelectWorkspaceFile: { _ in },
            onDiscardAllUnstaged: {},
            onRequestDiscard: { _, _ in },
            onRequestDeleteBranch: { _ in },
            onRequestSwitchBranch: { _ in },
            onCreateBranch: {},
            onRenameBranch: { _ in }
        )
        .frame(width: 360)
        .padding()
    }
}
