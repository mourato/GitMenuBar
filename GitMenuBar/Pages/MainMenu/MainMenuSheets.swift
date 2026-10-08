import SwiftUI

/// Attaches the main-menu sheets (branch dialogs, commit editor, sync
/// options, atomic commits) to the content view. Feature models own sheet
/// state and actions; stores arrive from the environment.
struct MainMenuSheetsModifier: ViewModifier {
    @Bindable var branchDialogs: MainMenuBranchDialogs
    let errorCenter: MainMenuErrorCenter
    @Bindable var workspace: MainMenuWorkspaceState
    @Bindable var sync: MainMenuSyncSheetState

    @Environment(GitManager.self) private var gitManager
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator
    @Environment(CommitHistoryEditCoordinator.self) private var commitHistoryEditCoordinator
    @Environment(AICommitCoordinator.self) private var aiCommitCoordinator
    @Environment(MainMenuPresentationModel.self) private var presentationModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $branchDialogs.showRenameBranch, content: renameBranchSheet)
            .sheet(
                isPresented: .init(
                    get: { commitHistoryEditCoordinator.isEditorPresented },
                    set: { isPresented in
                        if !isPresented {
                            commitHistoryEditCoordinator.dismissEditor()
                        }
                    }
                )
            ) { commitMessageEditorSheet() }
            .sheet(
                isPresented: Binding(
                    get: { actionCoordinator.showSyncOptions },
                    set: { actionCoordinator.showSyncOptions = $0 }
                ),
                content: syncOptionsSheet
            )
            .sheet(isPresented: $branchDialogs.showCreateBranch, content: createBranchSheet)
            .sheet(isPresented: $sync.showPullToNewBranch, content: pullToNewBranchSheet)
            .sheet(isPresented: $workspace.showAtomicCommitSheet, content: atomicCommitSheet)
    }

    private func saveEditedCommitMessage() {
        Task {
            if await commitHistoryEditCoordinator.saveDraftMessage() {
                presentationModel.showMain()
            }
        }
    }

    private func renameBranchSheet() -> some View {
        RenameBranchSheet(
            oldBranchName: branchDialogs.oldBranchName,
            newBranchName: $branchDialogs.renameBranchNewName,
            errorMessage: errorCenter.renameBranch,
            onCancel: {
                branchDialogs.showRenameBranch = false
                branchDialogs.renameBranchNewName = ""
                errorCenter.renameBranch = nil
            },
            onRename: { branchDialogs.renameBranch(using: actionCoordinator, errorCenter: errorCenter) }
        )
    }

    @ViewBuilder
    private func commitMessageEditorSheet() -> some View {
        if let editingCommit = commitHistoryEditCoordinator.editingCommit {
            CommitMessageEditorSheet(
                title: commitHistoryEditCoordinator.editMode.title,
                commit: editingCommit,
                message: Binding(
                    get: { commitHistoryEditCoordinator.draftMessage },
                    set: { commitHistoryEditCoordinator.draftMessage = $0 }
                ),
                isPublishedCommit: commitHistoryEditCoordinator.isPublishedCommit,
                isSaving: commitHistoryEditCoordinator.isSaving,
                errorMessage: commitHistoryEditCoordinator.inlineError,
                onCancel: {
                    commitHistoryEditCoordinator.dismissEditor()
                },
                onSave: saveEditedCommitMessage
            )
        }
    }

    private func syncOptionsSheet() -> some View {
        VStack(spacing: 16) {
            Text("Sync with Remote")
                .font(.headline.weight(.semibold))

            Text("Remote has \(gitManager.behindCount) new commit\(gitManager.behindCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                SyncOptionCard(
                    title: "Merge",
                    subtitle: "Safe: Creates a merge commit",
                    tone: .accent
                ) {
                    sync.useRebase = false
                    sync.syncWithRemote(using: actionCoordinator)
                }

                SyncOptionCard(
                    title: "Rebase",
                    subtitle: "Clean: Replays your commits on top",
                    tone: .warning
                ) {
                    sync.useRebase = true
                    sync.syncWithRemote(using: actionCoordinator)
                }

                SyncOptionCard(
                    title: "Pull to New Branch",
                    subtitle: "Safe: Creates a fresh branch from remote",
                    tone: .success
                ) {
                    actionCoordinator.dismissSyncOptions()
                    sync.pullToNewBranchName = "\(gitManager.currentBranch)-remote"
                    sync.showPullToNewBranch = true
                }
            }

            Button("Cancel") {
                actionCoordinator.dismissSyncOptions()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 320)
    }

    private func createBranchSheet() -> some View {
        CreateBranchSheet(
            branchName: $branchDialogs.newBranchName,
            currentBranch: gitManager.currentBranch,
            errorMessage: branchDialogs.createBranchError,
            onCancel: {
                branchDialogs.showCreateBranch = false
                branchDialogs.newBranchName = ""
                branchDialogs.createBranchError = nil
            },
            onCreate: { branchDialogs.createBranch(using: actionCoordinator) }
        )
    }

    private func pullToNewBranchSheet() -> some View {
        PullToNewBranchSheet(
            branchName: $sync.pullToNewBranchName,
            errorMessage: errorCenter.sync,
            onCancel: {
                sync.showPullToNewBranch = false
                sync.pullToNewBranchName = ""
                errorCenter.sync = nil
            },
            onPull: { sync.pullToNewBranch(using: actionCoordinator, errorCenter: errorCenter) }
        )
    }

    private func atomicCommitSheet() -> some View {
        AtomicCommitReviewSheet(
            gitManager: gitManager,
            makeSnapshot: { [gitManager] in
                try await gitManager.makeAtomicCommitSnapshotAsync()
            },
            generateGroups: { [weak aiCommitCoordinator] snapshot in
                guard let coordinator = aiCommitCoordinator else {
                    return []
                }
                return try await coordinator.generateAtomicHunkGroups(snapshot: snapshot)
            },
            onCancel: {
                workspace.showAtomicCommitSheet = false
            },
            onCommit: { executionPlan in
                workspace.showAtomicCommitSheet = false
                Task {
                    let result = await actionCoordinator.performReviewedAtomicCommits(plan: executionPlan)
                    if result.didCommit {
                        HapticFeedback.actionSucceeded()
                    }
                }
            }
        )
    }
}
