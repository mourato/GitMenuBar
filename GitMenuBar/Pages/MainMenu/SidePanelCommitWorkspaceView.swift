import SwiftUI

struct SidePanelCommitWorkspaceView: View {
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

    @Environment(GitManager.self) private var gitManager
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator
    @Environment(CommitHistoryEditCoordinator.self) private var commitHistoryEditCoordinator
    @AppStorage(AppPreferences.Keys.workingTreeDisplayMode)
    private var displayMode = AppPreferences.WorkingTreeDisplayMode.tree
    @State private var isStagedCollapsed = false
    @State private var isUnstagedCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            SidePanelHeaderView(
                projectName: projectName,
                title: "Working Tree",
                onClose: onClose,
                onStash: stashChanges
            )
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
                commitFileCount: commitFileCount,
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
                workingTreeContent
            }
        }
    }

    private func stashChanges() {
        guard !isCommitActionBusy, !actionCoordinator.isBusy else { return }
        Task {
            _ = await actionCoordinator.sidePanel.saveSidePanelStash()
        }
    }

    private var workingTreeContent: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            if gitManager.stagedFiles.isEmpty, gitManager.changedFiles.isEmpty {
                WorkingTreeCleanStateView(
                    lastCommitSubject: gitManager.commitHistory.first?.subject,
                    lastCommitRelativeDate: gitManager.commitHistory.first.map {
                        $0.committedAt.formatted(.relative(presentation: .named))
                    },
                    aheadCount: gitManager.isAheadOfRemote ? gitManager.commitCount : 0,
                    onPush: {
                        Task { _ = await actionCoordinator.performSync() }
                    }
                )
            } else {
                WorkingTreeSectionView(
                    title: "Staged",
                    summary: gitManager.stagedFiles.sectionSummary,
                    files: gitManager.stagedFiles.map(WorkingTreeRowAdapter.staged(file:)),
                    isCollapsed: $isStagedCollapsed,
                    displayMode: $displayMode,
                    selectedItemID: workspaceSelectedFileID,
                    onSelect: onSelectWorkspaceFile,
                    onStageToggle: { path in
                        Task { _ = await actionCoordinator.sidePanel.unstageSidePanelFile(path: path) }
                    },
                    onOpen: { gitManager.openFile(path: $0) },
                    onDiscard: onRequestDiscard,
                    onReveal: { gitManager.revealInFinder(path: $0) },
                    onAction: {
                        Task { _ = await actionCoordinator.sidePanel.unstageAllSidePanelFiles() }
                    },
                    onDiscardAll: nil,
                    actionIcon: "minus.circle",
                    actionHelp: "Unstage all staged changes",
                    showsViewModeToggle: gitManager.changedFiles.isEmpty,
                    showsEmptyState: true
                )

                if !gitManager.changedFiles.isEmpty {
                    WorkingTreeSectionView(
                        title: "Unstaged",
                        summary: gitManager.changedFiles.sectionSummary,
                        files: gitManager.changedFiles.map(WorkingTreeRowAdapter.unstaged(file:)),
                        isCollapsed: $isUnstagedCollapsed,
                        displayMode: $displayMode,
                        selectedItemID: workspaceSelectedFileID,
                        onSelect: onSelectWorkspaceFile,
                        onStageToggle: { path in
                            Task { _ = await actionCoordinator.sidePanel.stageSidePanelFile(path: path) }
                        },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: onRequestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: {
                            Task { _ = await actionCoordinator.sidePanel.stageAllSidePanelFiles() }
                        },
                        onDiscardAll: onDiscardAllUnstaged,
                        actionIcon: "plus.circle",
                        actionHelp: "Stage all unstaged changes",
                        showsViewModeToggle: true
                    )
                }
            }
        }
    }

    private var commitFileCount: Int {
        gitManager.stagedFiles.isEmpty ? gitManager.changedFiles.count : gitManager.stagedFiles.count
    }
}

#Preview("Commit Workspace") {
    MainMenuPreviewHarness {
        SidePanelCommitWorkspacePreviewHost()
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth, height: 640)
}

private struct SidePanelCommitWorkspacePreviewHost: View {
    @State private var commitMessage = ""
    @FocusState private var isCommitFieldFocused: Bool

    var body: some View {
        SidePanelCommitWorkspaceView(
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
            onRequestDiscard: { _, _ in }
        )
    }
}
