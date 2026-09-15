import SwiftUI

extension MainMenuView {
    func renameBranchSheet() -> some View {
        RenameBranchSheet(
            oldBranchName: oldBranchName,
            newBranchName: $renameBranchNewName,
            errorMessage: errorCenter.renameBranch,
            onCancel: {
                showRenameBranch = false
                renameBranchNewName = ""
                errorCenter.renameBranch = nil
            },
            onRename: renameBranch
        )
    }

    @ViewBuilder
    func commitMessageEditorSheet() -> some View {
        if let editingCommit = commitHistoryEditCoordinator.editingCommit {
            CommitMessageEditorSheet(
                title: commitHistoryEditCoordinator.editMode.title,
                commit: editingCommit,
                message: $commitHistoryEditCoordinator.draftMessage,
                isPublishedCommit: commitHistoryEditCoordinator.isPublishedCommit,
                isSaving: commitHistoryEditCoordinator.isSaving,
                errorMessage: commitHistoryEditCoordinator.inlineError,
                onCancel: {
                    commitHistoryEditCoordinator.dismissEditor()
                },
                onSave: {
                    Task {
                        await saveEditedCommitMessage()
                    }
                }
            )
        }
    }

    func syncOptionsSheet() -> some View {
        VStack(spacing: 16) {
            Text("Sync with Remote")
                .font(.headline.weight(.semibold))

            Text(syncOptionsSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                SyncOptionCard(
                    title: "Merge",
                    subtitle: "Safe: Creates a merge commit",
                    tone: .accent
                ) {
                    useRebase = false
                    syncWithRemote()
                }

                SyncOptionCard(
                    title: "Rebase",
                    subtitle: "Clean: Replays your commits on top",
                    tone: .warning
                ) {
                    useRebase = true
                    syncWithRemote()
                }

                SyncOptionCard(
                    title: "Pull to New Branch",
                    subtitle: "Safe: Creates a fresh branch from remote",
                    tone: .success
                ) {
                    actionCoordinator.dismissSyncOptions()
                    pullToNewBranchName = "\(gitManager.currentBranch)-remote"
                    showPullToNewBranch = true
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

    var syncOptionsSubtitle: String {
        "Remote has \(gitManager.behindCount) new commit\(gitManager.behindCount == 1 ? "" : "s")"
    }

    func createBranchSheet() -> some View {
        CreateBranchSheet(
            branchName: $newBranchName,
            currentBranch: gitManager.currentBranch,
            errorMessage: createBranchError,
            onCancel: {
                showCreateBranch = false
                newBranchName = ""
                createBranchError = nil
            },
            onCreate: createNewBranch
        )
    }

    func pullToNewBranchSheet() -> some View {
        PullToNewBranchSheet(
            branchName: $pullToNewBranchName,
            errorMessage: errorCenter.sync,
            onCancel: {
                showPullToNewBranch = false
                pullToNewBranchName = ""
                errorCenter.sync = nil
            },
            onPull: pullToNewBranch
        )
    }

    func atomicCommitSheet() -> some View {
        AtomicCommitReviewSheet(
            gitManager: gitManager,
            makeSnapshot: { [weak gitManager] in
                await gitManager?.makeAtomicCommitSnapshotAsync()
            },
            generateGroups: { [weak aiCommitCoordinator] snapshot in
                guard let coordinator = aiCommitCoordinator else {
                    return []
                }
                return try await coordinator.generateAtomicHunkGroups(snapshot: snapshot)
            },
            onCancel: {
                showAtomicCommitSheet = false
            },
            onCommit: { executionPlan in
                showAtomicCommitSheet = false
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
