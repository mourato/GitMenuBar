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
    let history: SidePanelHistoryModel
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

    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @EnvironmentObject private var commitHistoryEditCoordinator: CommitHistoryEditCoordinator
    @State private var isStagedCollapsed = false
    @State private var isUnstagedCollapsed = false
    @State private var pendingReset: Commit?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            SidePanelHeaderView(
                projectName: projectName,
                title: "Working Tree",
                onClose: onClose
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
                    SidePanelHistoryBrowserView(history: history, pendingReset: $pendingReset)
                }
            }
        }
        .sidePanelResetAlert(commit: $pendingReset) { commit in
            Task {
                _ = await actionCoordinator.resetSidePanelCommit(hash: commit.id)
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
                HStack {
                    Spacer(minLength: 0)
                    Button("Stash changes") {
                        Task { _ = await actionCoordinator.saveSidePanelStash() }
                    }
                    .workbenchGhost()
                    .disabled(isCommitActionBusy || actionCoordinator.isBusy)
                    .accessibilityHint("Parks working tree changes in a stash without committing")
                }
                if !gitManager.stagedFiles.isEmpty {
                    WorkingTreeSectionView(
                        title: "Staged",
                        summary: gitManager.stagedFiles.sectionSummary,
                        files: gitManager.stagedFiles.map(WorkingTreeRowAdapter.staged(file:)),
                        isCollapsed: $isStagedCollapsed,
                        selectedItemID: workspaceSelectedFileID,
                        onSelect: onSelectWorkspaceFile,
                        onStageToggle: { path in
                            Task { _ = await actionCoordinator.unstageSidePanelFile(path: path) }
                        },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: onRequestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: {
                            Task { _ = await actionCoordinator.unstageAllSidePanelFiles() }
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
                            Task { _ = await actionCoordinator.stageSidePanelFile(path: path) }
                        },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: onRequestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: {
                            Task { _ = await actionCoordinator.stageAllSidePanelFiles() }
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
            history: .preview(),
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
