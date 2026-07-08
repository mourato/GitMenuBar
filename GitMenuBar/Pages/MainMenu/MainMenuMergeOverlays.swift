//
//  MainMenuMergeOverlays.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    /// Wraps the merge-into-default-branch flow overlays: a pre-merge
    /// confirmation, a post-merge cleanup picker, and a second confirmation for
    /// any remote-branch deletion (which is irreversible and affects collaborators).
    func applyMergeToDefaultOverlays<Content: View>(to view: Content) -> some View {
        view
            .alert(
                "Merge '\(featureBranchName)' into \(defaultBranchName)?",
                isPresented: $showMergeToDefaultConfirmation
            ) {
                Button("Merge") {
                    performMergeToDefault()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    featureBranchName = ""
                    defaultBranchName = ""
                }
            } message: {
                Text(
                    "This brings all changes from '\(featureBranchName)' into \(defaultBranchName). "
                        + "Uncommitted changes are stashed and restored. The feature branch is kept "
                        + "so you can clean it up afterwards."
                )
            }
            .confirmationDialog(
                "Clean up '\(featureBranchName)'?",
                isPresented: $showMergeCleanupDialog,
                titleVisibility: .visible
            ) {
                Button("Delete Local Only", role: .destructive) {
                    performMergeCleanup(option: .deleteLocal)
                }
                Button("Delete Local & Remote", role: .destructive) {
                    requestRemoteCleanupConfirmation(option: .deleteLocalAndRemote)
                }
                Button("Delete Remote Only", role: .destructive) {
                    requestRemoteCleanupConfirmation(option: .deleteRemoteOnly)
                }
                Button("Keep Branch", role: .cancel) {
                    dismissMergeCleanup()
                }
            } message: {
                Text(
                    "'\(featureBranchName)' is merged into \(defaultBranchName). You can delete the "
                        + "feature branch now or keep it."
                )
            }
            .alert(
                "Delete remote branch '\(featureBranchName)'?",
                isPresented: $showRemoteCleanupConfirmation
            ) {
                Button("Delete Remote", role: .destructive) {
                    if let option = pendingCleanupOption {
                        performMergeCleanup(option: option)
                    }
                    pendingCleanupOption = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingCleanupOption = nil
                }
            } message: {
                Text(
                    "This permanently removes '\(featureBranchName)' from the remote. Other collaborators "
                        + "may be affected, and this cannot be undone."
                )
            }
    }
}
