import SwiftUI

struct InspectorCommitWorkspaceView: View {
    let projectName: String
    @Binding var commitMessage: String
    let commitFieldFocus: FocusState<Bool>.Binding
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
    let history: InspectorHistoryModel
    let workspaceSelectedFileID: MainMenuSelectableItem?
    let onCommitPrimaryAction: () -> Void
    let onSplitCommits: () -> Void
    let onRetryCommitGeneration: () -> Void
    let onUseCommitFallbackModel: () -> Void
    let onCommitDidCommit: () -> Void
    let onRequestCommitFocus: () -> Void
    let onSelectWorkspaceFile: (MainMenuSelectableItem) -> Void
    let onDiscardAllUnstaged: () -> Void
    let onRequestDiscard: (String, WorkingTreeFileStatus) -> Void

    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @EnvironmentObject private var commitHistoryEditCoordinator: CommitHistoryEditCoordinator
    @State private var isStagedCollapsed = false
    @State private var isUnstagedCollapsed = false
    @State private var pendingReset: Commit?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            InspectorHeaderView(projectName: projectName, title: "Working Tree")
            CommitWorkflowView(
                commentText: $commitMessage,
                isCommentFieldFocused: commitFieldFocus,
                showsCommentField: showsCommitField,
                primaryButtonSystemImage: commitPrimaryButtonSystemImage,
                isPrimaryActionBusy: isCommitActionBusy,
                automaticMessageHint: commitAutomaticMessageHint,
                generationDisabledReason: commitGenerationDisabledReason,
                generationError: commitGenerationError,
                automaticRetryAvailable: commitAutomaticRetryAvailable,
                isFallbackModelAvailable: isCommitFallbackModelAvailable,
                primaryButtonTitle: commitPrimaryButtonTitle,
                isPrimaryButtonDisabled: isCommitPrimaryButtonDisabled,
                canShowSplitCommits: canShowSplitCommits,
                onPrimaryAction: onCommitPrimaryAction,
                onSplitCommits: onSplitCommits,
                onRetryGeneration: onRetryCommitGeneration,
                onUseFallbackModel: onUseCommitFallbackModel,
                onDidCommit: onCommitDidCommit,
                onRequestFocus: onRequestCommitFocus,
                focusCommitFieldToken: commitFocusToken,
                actionCoordinator: actionCoordinator,
                commitHistoryEditCoordinator: commitHistoryEditCoordinator
            )
            ScrollView {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
                    workingTreeContent
                    InspectorHistoryBrowserView(history: history, pendingReset: $pendingReset)
                }
            }
        }
        .inspectorResetAlert(commit: $pendingReset) { commit in
            Task {
                _ = await actionCoordinator.resetInspectorCommit(hash: commit.id)
            }
        }
    }

    private var workingTreeContent: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            if gitManager.stagedFiles.isEmpty, gitManager.changedFiles.isEmpty {
                ContentUnavailableView(
                    "Working tree is clean",
                    systemImage: "checkmark.circle",
                    description: Text("Stage files to start a commit.")
                )
            } else {
                if !gitManager.stagedFiles.isEmpty {
                    WorkingTreeSectionView(
                        title: "Staged",
                        summary: gitManager.stagedFiles.sectionSummary,
                        files: gitManager.stagedFiles.map(WorkingTreeRowAdapter.staged(file:)),
                        isCollapsed: $isStagedCollapsed,
                        selectedItemID: workspaceSelectedFileID,
                        onSelect: onSelectWorkspaceFile,
                        onStageToggle: { path in
                            Task { _ = await actionCoordinator.unstageInspectorFile(path: path) }
                        },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: onRequestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: {
                            Task { _ = await actionCoordinator.unstageAllInspectorFiles() }
                        },
                        onDiscardAll: nil,
                        actionIcon: "minus.circle",
                        actionHelp: "Unstage all files"
                    )
                }
                if !gitManager.changedFiles.isEmpty {
                    WorkingTreeSectionView(
                        title: "Unstaged",
                        summary: gitManager.changedFiles.sectionSummary,
                        files: gitManager.changedFiles.map(WorkingTreeRowAdapter.unstaged(file:)),
                        isCollapsed: $isUnstagedCollapsed,
                        selectedItemID: workspaceSelectedFileID,
                        onSelect: onSelectWorkspaceFile,
                        onStageToggle: { path in
                            Task { _ = await actionCoordinator.stageInspectorFile(path: path) }
                        },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: onRequestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: {
                            Task { _ = await actionCoordinator.stageAllInspectorFiles() }
                        },
                        onDiscardAll: onDiscardAllUnstaged,
                        actionIcon: "plus.circle",
                        actionHelp: "Stage all files"
                    )
                }
            }
        }
    }
}

#Preview("Commit Workspace") {
    MainMenuPreviewHarness {
        InspectorCommitWorkspacePreviewHost()
    }
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 640)
}

private struct InspectorCommitWorkspacePreviewHost: View {
    @State private var commitMessage = ""
    @FocusState private var isCommitFieldFocused: Bool

    var body: some View {
        InspectorCommitWorkspaceView(
            projectName: "GitMenuBar",
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
            commitFocusToken: 0,
            history: .preview(),
            workspaceSelectedFileID: nil,
            onCommitPrimaryAction: {},
            onSplitCommits: {},
            onRetryCommitGeneration: {},
            onUseCommitFallbackModel: {},
            onCommitDidCommit: {},
            onRequestCommitFocus: {},
            onSelectWorkspaceFile: { _ in },
            onDiscardAllUnstaged: {},
            onRequestDiscard: { _, _ in }
        )
    }
}
