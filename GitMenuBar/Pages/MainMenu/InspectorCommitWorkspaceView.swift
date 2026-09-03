import SwiftUI

struct InspectorCommitWorkspaceView: View {
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
    let workspaceSelectedFileID: MainMenuSelectableItem?
    let commitFocusToken: Int
    let historySections: [HistoryTimelineSectionModel]
    let historySelectedItemID: MainMenuSelectableItem?
    let isHistoryLoading: Bool
    let canLoadMoreHistory: Bool
    let animationNamespace: Namespace.ID
    let onCommitPrimaryAction: () -> Void
    let onSplitCommits: () -> Void
    let onRetryCommitGeneration: () -> Void
    let onUseCommitFallbackModel: () -> Void
    let onCommitDidCommit: () -> Void
    let onRequestCommitFocus: () -> Void
    let onSelectWorkspaceFile: (MainMenuSelectableItem) -> Void
    let onDiscardAllUnstaged: () -> Void
    let onRequestDiscard: (String, WorkingTreeFileStatus) -> Void
    let onSelectHistoryRow: (HistoryRowAdapter) -> Void
    let onOpenHistoryCommit: (String) -> Void
    let onEditCommitMessage: (Commit) -> Void
    let onGenerateCommitMessage: (Commit) -> Void
    let onLoadMoreHistory: () -> Void

    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @EnvironmentObject private var commitHistoryEditCoordinator: CommitHistoryEditCoordinator
    @State private var isStagedCollapsed = false
    @State private var isUnstagedCollapsed = false
    @State private var isHistoryCollapsed = false
    @State private var pendingReset: Commit?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
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
                    HistorySectionView(
                        sections: historySections,
                        selectedItemID: historySelectedItemID,
                        isLoading: isHistoryLoading,
                        canLoadMore: canLoadMoreHistory,
                        animationNamespace: animationNamespace,
                        onSelectRow: onSelectHistoryRow,
                        onActivateCommit: { row in
                            onOpenHistoryCommit(row.commit.id)
                        },
                        onRestoreCommit: { row in
                            guard row.actions.canRestore else { return }
                            pendingReset = row.commit
                        },
                        onEditCommitMessage: { row in
                            onEditCommitMessage(row.commit)
                        },
                        onGenerateCommitMessage: { row in
                            onGenerateCommitMessage(row.commit)
                        },
                        onLoadMore: onLoadMoreHistory,
                        isCollapsed: $isHistoryCollapsed
                    )
                }
            }
        }
        .alert(
            "Reset to this commit?",
            isPresented: Binding(
                get: { pendingReset != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingReset = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingReset = nil
            }
            Button("Reset", role: .destructive) {
                guard let pendingReset else { return }
                let commit = pendingReset
                self.pendingReset = nil
                Task {
                    _ = await actionCoordinator.resetInspectorCommit(hash: commit.id)
                }
            }
        } message: {
            if let pendingReset {
                Text(
                    "This hard-resets the current branch to \(pendingReset.shortHash) (\(pendingReset.subject)). Uncommitted work may be lost."
                )
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
    @Namespace private var animationNamespace
    @State private var commitMessage = ""
    @FocusState private var isCommitFieldFocused: Bool

    var body: some View {
        InspectorCommitWorkspaceView(
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
            historySections: [],
            historySelectedItemID: nil,
            isHistoryLoading: false,
            canLoadMoreHistory: false,
            animationNamespace: animationNamespace,
            onCommitPrimaryAction: {},
            onSplitCommits: {},
            onRetryCommitGeneration: {},
            onUseCommitFallbackModel: {},
            onCommitDidCommit: {},
            onRequestCommitFocus: {},
            onSelectWorkspaceFile: { _ in },
            onDiscardAllUnstaged: {},
            onRequestDiscard: { _, _ in },
            onSelectHistoryRow: { _ in },
            onOpenHistoryCommit: { _ in },
            onEditCommitMessage: { _ in },
            onGenerateCommitMessage: { _ in },
            onLoadMoreHistory: {}
        )
    }
}
