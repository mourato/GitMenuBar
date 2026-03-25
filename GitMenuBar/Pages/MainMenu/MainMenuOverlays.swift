//
//  MainMenuOverlays.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    // swiftlint:disable:next function_body_length
    func applyMainViewOverlays<Content: View>(to view: Content) -> some View {
        view
            .alert(item: $actionCoordinator.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .cancel(Text("OK")) {
                        actionCoordinator.clearAlert()
                    }
                )
            }
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
                    "The current message has no visible text. You can cancel, commit with the current text, or ignore it and generate a message automatically."
                )
            }
            .alert("Push Failed", isPresented: .init(
                get: { pushError != nil },
                set: { if !$0 { pushError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pushError ?? "An unknown error occurred.")
            }
            .alert("Sync Failed", isPresented: .init(
                get: { syncError != nil },
                set: { if !$0 { syncError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncError ?? "An unknown error occurred.")
            }
            .alert("Branch Switch Failed", isPresented: .init(
                get: { branchSwitchError != nil },
                set: { if !$0 { branchSwitchError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(branchSwitchError ?? "An unknown error occurred.")
            }
            .alert("Merge Failed", isPresented: .init(
                get: { mergeError != nil },
                set: { if !$0 { mergeError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mergeError ?? "An unknown error occurred.")
            }
            .alert("Delete Failed", isPresented: .init(
                get: { deleteBranchError != nil },
                set: { if !$0 { deleteBranchError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteBranchError ?? "An unknown error occurred.")
            }
            .alert("Rename Failed", isPresented: .init(
                get: { renameBranchError != nil },
                set: { if !$0 { renameBranchError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(renameBranchError ?? "An unknown error occurred.")
            }
            .alert("Restart GitMenuBar?", isPresented: $showRestartConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Restart") {
                    restartApplication()
                }
            } message: {
                Text("This will relaunch the app immediately.")
            }
            .alert("Restart Failed", isPresented: .init(
                get: { restartError != nil },
                set: { if !$0 { restartError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restartError ?? "An unknown error occurred.")
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
                Text("This will bring all changes from '\(mergeBranchName)' into your current branch '\(mergeTargetBranch)'.")
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
                    (branchNameToDelete == "main" || branchNameToDelete == "master" || branchNameToDelete == "develop") ?
                        "WARNING: '\(branchNameToDelete)' is a primary branch. Deleting it may cause serious issues." :
                        "Are you sure you want to delete this branch? This action cannot be undone."
                )
            }

            .sheet(isPresented: $showRenameBranch) {
                RenameBranchSheet(
                    oldBranchName: oldBranchName,
                    newBranchName: $renameBranchNewName,
                    onCancel: {
                        showRenameBranch = false
                        renameBranchNewName = ""
                    },
                    onRename: renameBranch
                )
            }
            .sheet(isPresented: $actionCoordinator.showSyncOptions) {
                VStack(spacing: 16) {
                    Text("Sync with Remote")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Remote has \(gitManager.behindCount) new commit\(gitManager.behindCount == 1 ? "" : "s")")
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
            .sheet(isPresented: $showCreateBranch) {
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
            .sheet(isPresented: $showPullToNewBranch) {
                PullToNewBranchSheet(
                    branchName: $pullToNewBranchName,
                    onCancel: {
                        showPullToNewBranch = false
                        pullToNewBranchName = ""
                    },
                    onPull: pullToNewBranch
                )
            }
            .overlay {
                if isCommandPalettePresented && presentationModel.route == .main {
                    ZStack {
                        Color.black.opacity(0.22)
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
                        .zIndex(1)
                    }
                }
            }
    }
}

#Preview("Main Overlays") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
