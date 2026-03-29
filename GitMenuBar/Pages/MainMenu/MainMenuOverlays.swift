//
//  MainMenuOverlays.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    func applyMainViewOverlays<Content: View>(to view: Content) -> some View {
        let commitAndRewriteOverlays = applyWhitespaceAndRewriteOverlays(to: view)
        let confirmationAlerts = applyConfirmationAlerts(to: commitAndRewriteOverlays)
        let sheets = applySheets(to: confirmationAlerts)
        return applyCommandPaletteOverlay(to: sheets)
    }

    private func applyWhitespaceAndRewriteOverlays<Content: View>(to view: Content) -> some View {
        let editAlertView = applyCommitEditAlert(to: view)
        let whitespaceView = applyWhitespaceCommitConfirmation(to: editAlertView)
        return applyPublishedRewriteConfirmation(to: whitespaceView)
    }

    private func applyCommitEditAlert<Content: View>(to view: Content) -> some View {
        view
            .alert(item: $commitHistoryEditCoordinator.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .cancel(Text("OK")) {
                        commitHistoryEditCoordinator.clearAlert()
                    }
                )
            }
    }

    private func applyWhitespaceCommitConfirmation<Content: View>(to view: Content) -> some View {
        view
            .confirmationDialog(
                "Commit message contains only spaces",
                isPresented: .init(
                    get: { actionCoordinator.whitespaceCommitPrompt != nil },
                    set: { isPresented in
                        if !isPresented {
                            actionCoordinator.dismissWhitespaceCommitPrompt()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let prompt = actionCoordinator.whitespaceCommitPrompt {
                    Button("Commit As Typed") {
                        Task {
                            let result = await actionCoordinator.commitUsingCurrentWhitespaceMessage(
                                prompt.rawCommentText,
                                shouldPushAfterCommit: prompt.shouldPushAfterCommit
                            )
                            if result.didCommit {
                                commentText = ""
                                if hideCommitMessageField {
                                    isCommitFieldTemporarilyVisible = false
                                }
                            }
                        }
                    }

                    Button("Generate Message") {
                        Task {
                            let result = await actionCoordinator.commitByGeneratingMessage(
                                afterDiscardingWhitespace: prompt.rawCommentText,
                                shouldPushAfterCommit: prompt.shouldPushAfterCommit
                            )
                            if result.didCommit {
                                commentText = ""
                                if hideCommitMessageField {
                                    isCommitFieldTemporarilyVisible = false
                                }
                            }
                        }
                    }
                }

                Button("Cancel", role: .cancel) {
                    actionCoordinator.dismissWhitespaceCommitPrompt()
                }
            } message: {
                Text(
                    "The current message has no visible text. You can cancel, commit with the current text, "
                        + "or ignore it and generate a message automatically."
                )
            }
    }

    private func applyPublishedRewriteConfirmation<Content: View>(to view: Content) -> some View {
        view
            .confirmationDialog(
                "Rewrite Published Commit?",
                isPresented: .init(
                    get: { commitHistoryEditCoordinator.rewriteConfirmation != nil },
                    set: { isPresented in
                        if !isPresented {
                            commitHistoryEditCoordinator.dismissRewriteConfirmation()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Rewrite Commit", role: .destructive) {
                    Task {
                        await confirmPublishedCommitRewrite()
                    }
                }

                Button("Cancel", role: .cancel) {
                    commitHistoryEditCoordinator.dismissRewriteConfirmation()
                }
            } message: {
                Text(
                    "This commit already exists on the remote. Rewriting it changes local history "
                        + "and your next push may require force push."
                )
            }
    }

    private func applyConfirmationAlerts<Content: View>(to view: Content) -> some View {
        view
            .alert("Restart GitMenuBar?", isPresented: $showRestartConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Restart") {
                    restartApplication()
                }
                .keyboardShortcut(.defaultAction)
            } message: {
                Text("This will relaunch the app immediately.")
            }
            .alert("Merge into \(mergeTargetBranch)?", isPresented: $showMergeConfirmation) {
                Button("Merge") {
                    gitManager.mergeBranch(fromBranch: mergeBranchName) { result in
                        if case let .failure(error) = result {
                            mergeError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    mergeBranchName = ""
                    mergeTargetBranch = ""
                }
            } message: {
                Text(
                    "This will bring all changes from '\(mergeBranchName)' into your current branch "
                        + "'\(mergeTargetBranch)'."
                )
            }
            .alert("Uncommitted Changes", isPresented: $showDirtySwitchConfirmation) {
                Button("Switch & Carry Over") {
                    gitManager.switchBranch(branchName: pendingSwitchBranch) { result in
                        if case let .failure(error) = result {
                            branchSwitchError = error.localizedDescription
                        }
                    }
                    pendingSwitchBranch = ""
                }
                Button("Cancel", role: .cancel) {
                    pendingSwitchBranch = ""
                }
            } message: {
                Text("You have uncommitted changes. They will follow you to '\(pendingSwitchBranch)'.")
            }
            .alert("Delete '\(branchNameToDelete)'?", isPresented: $showBranchDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    gitManager.deleteBranch(branchName: branchNameToDelete) { result in
                        if case let .failure(error) = result {
                            deleteBranchError = error.localizedDescription
                        }
                    }
                    branchNameToDelete = ""
                }
                Button("Cancel", role: .cancel) {
                    branchNameToDelete = ""
                }
            } message: {
                Text(
                    deleteBranchWarningMessage
                )
            }
    }

    private func applySheets<Content: View>(to view: Content) -> some View {
        view
            .sheet(isPresented: $showRenameBranch, content: renameBranchSheet)
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
            .sheet(isPresented: $actionCoordinator.showSyncOptions, content: syncOptionsSheet)
            .sheet(isPresented: $showCreateBranch, content: createBranchSheet)
            .sheet(isPresented: $showPullToNewBranch, content: pullToNewBranchSheet)
    }

    private func applyCommandPaletteOverlay<Content: View>(to view: Content) -> some View {
        view.overlay {
            if isCommandPalettePresented && presentationModel.route == .main {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeCommandPalette()
                        }
                        .zIndex(0)

                    MainMenuCommandPaletteView(
                        query: $commandPaletteQuery,
                        items: commandPaletteVisibleItems,
                        selectedItemID: $selectedCommandPaletteItemID,
                        onClose: closeCommandPalette,
                        onSelectItem: executeCommandPaletteItem
                    )
                    .accessibilityAddTraits(.isModal)
                    .zIndex(1)
                }
            }
        }
    }

    private var deleteBranchWarningMessage: String {
        let protectedBranches = ["main", "master", "develop"]
        if protectedBranches.contains(branchNameToDelete) {
            return "WARNING: '\(branchNameToDelete)' is a primary branch. Deleting it may cause serious issues."
        }

        return "Are you sure you want to delete this branch? This action cannot be undone."
    }

    private func renameBranchSheet() -> some View {
        RenameBranchSheet(
            oldBranchName: oldBranchName,
            newBranchName: $renameBranchNewName,
            errorMessage: renameBranchError,
            onCancel: {
                showRenameBranch = false
                renameBranchNewName = ""
                renameBranchError = nil
            },
            onRename: renameBranch
        )
    }

    @ViewBuilder
    private func commitMessageEditorSheet() -> some View {
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

    private func syncOptionsSheet() -> some View {
        VStack(spacing: 16) {
            Text("Sync with Remote")
                .font(.system(size: 14, weight: .semibold))

            Text(syncOptionsSubtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                SyncOptionCard(
                    title: "Merge",
                    subtitle: "Safe: Creates a merge commit",
                    backgroundColor: Color.blue.opacity(0.1)
                ) {
                    useRebase = false
                    syncWithRemote()
                }

                SyncOptionCard(
                    title: "Rebase",
                    subtitle: "Clean: Replays your commits on top",
                    backgroundColor: Color.purple.opacity(0.1)
                ) {
                    useRebase = true
                    syncWithRemote()
                }

                SyncOptionCard(
                    title: "Pull to New Branch",
                    subtitle: "Safe: Creates a fresh branch from remote",
                    backgroundColor: Color.green.opacity(0.1)
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
            .foregroundColor(.secondary)
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 320)
    }

    private var syncOptionsSubtitle: String {
        "Remote has \(gitManager.behindCount) new commit\(gitManager.behindCount == 1 ? "" : "s")"
    }

    private func createBranchSheet() -> some View {
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

    private func pullToNewBranchSheet() -> some View {
        PullToNewBranchSheet(
            branchName: $pullToNewBranchName,
            errorMessage: syncError,
            onCancel: {
                showPullToNewBranch = false
                pullToNewBranchName = ""
                syncError = nil
            },
            onPull: pullToNewBranch
        )
    }
}

#Preview("Main Overlays") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
