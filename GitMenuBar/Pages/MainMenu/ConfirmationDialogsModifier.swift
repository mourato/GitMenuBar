import SwiftUI

struct ConfirmationDialogsModifier: ViewModifier {
    @Bindable var dialogs: MainMenuBranchDialogs
    @Binding var showDeleteConfirmation: Bool
    @Binding var showVisibilityConfirmation: Bool
    @Binding var showDiscardConfirmation: Bool
    @Binding var showDiscardAllConfirmation: Bool
    @Binding var showRestartConfirmation: Bool

    let isDeleting: Bool
    let isTogglingVisibility: Bool
    let visibilityConfirmationTitle: String
    let visibilityActionTitle: String
    let visibilityConfirmationMessage: String
    let deleteBranchWarningMessage: String

    let onDeleteRepository: () -> Void
    let onToggleVisibility: () -> Void
    let onDiscardConfirm: () -> Void
    let onDiscardAll: () -> Void
    let onRestart: () -> Void
    let onMerge: () -> Void
    let onCancelMerge: () -> Void
    let onDirtySwitch: () -> Void
    let onCancelDirtySwitch: () -> Void
    let onDeleteBranch: () -> Void
    let onCancelDeleteBranch: () -> Void
    let onMergeToDefault: () -> Void
    let onCancelMergeToDefault: () -> Void
    let onMergeCleanupDeleteLocal: () -> Void
    let onMergeCleanupDeleteLocalAndRemote: () -> Void
    let onMergeCleanupDeleteRemoteOnly: () -> Void
    let onMergeCleanupKeep: () -> Void
    let onRemoteCleanupDelete: () -> Void
    let onRemoteCleanupCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Delete Repository?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: onDeleteRepository)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isDeleting)
            } message: {
                Text("This will permanently delete the repository from GitHub. This action cannot be undone.")
            }
            .alert(visibilityConfirmationTitle, isPresented: $showVisibilityConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button(visibilityActionTitle, action: onToggleVisibility)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isTogglingVisibility)
            } message: {
                Text(visibilityConfirmationMessage)
            }
            .alert("Discard Changes?", isPresented: $showDiscardConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Discard", role: .destructive, action: onDiscardConfirm)
                    .keyboardShortcut(.defaultAction)
            }
            .alert("Discard All Unstaged Changes?", isPresented: $showDiscardAllConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Discard All", role: .destructive, action: onDiscardAll)
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text("Are you sure you want to discard all unstaged changes? This action cannot be undone.")
            }
            .alert("Restart GitMenuBar?", isPresented: $showRestartConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Restart", action: onRestart)
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text("This will relaunch the app immediately.")
            }
            .alert("Merge into \(dialogs.mergeTargetBranch)?", isPresented: $dialogs.showMergeConfirmation) {
                Button("Merge", action: onMerge)
                Button("Cancel", role: .cancel, action: onCancelMerge)
            } message: {
                Text("This will bring all changes from '\(dialogs.mergeBranchName)' into your current branch '\(dialogs.mergeTargetBranch)'.")
            }
            .alert("Uncommitted Changes", isPresented: $dialogs.showDirtySwitchConfirmation) {
                Button("Switch & Carry Over", action: onDirtySwitch)
                Button("Cancel", role: .cancel, action: onCancelDirtySwitch)
            } message: {
                Text("You have uncommitted changes. They will follow you to '\(dialogs.pendingSwitchBranch)'.")
            }
            .alert("Delete '\(dialogs.branchNameToDelete)'?", isPresented: $dialogs.showBranchDeleteConfirmation) {
                Button("Delete", role: .destructive, action: onDeleteBranch)
                Button("Cancel", role: .cancel, action: onCancelDeleteBranch)
            } message: {
                Text(deleteBranchWarningMessage)
            }
            .alert("Merge '\(dialogs.featureBranchName)' into \(dialogs.defaultBranchName)?", isPresented: $dialogs.showMergeToDefaultConfirmation) {
                Button("Merge", action: onMergeToDefault)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel, action: onCancelMergeToDefault)
            } message: {
                Text("This brings all changes from '\(dialogs.featureBranchName)' into \(dialogs.defaultBranchName). Uncommitted changes are stashed and restored. The feature branch is kept so you can clean it up afterwards.")
            }
            .confirmationDialog("Clean up '\(dialogs.featureBranchName)'?", isPresented: $dialogs.showMergeCleanupDialog, titleVisibility: .visible) {
                Button("Delete Local Only", role: .destructive, action: onMergeCleanupDeleteLocal)
                Button("Delete Local & Remote", role: .destructive, action: onMergeCleanupDeleteLocalAndRemote)
                Button("Delete Remote Only", role: .destructive, action: onMergeCleanupDeleteRemoteOnly)
                Button("Keep Branch", role: .cancel, action: onMergeCleanupKeep)
            } message: {
                Text("'\(dialogs.featureBranchName)' is merged into \(dialogs.defaultBranchName). You can delete the feature branch now or keep it.")
            }
            .alert("Delete remote branch '\(dialogs.featureBranchName)'?", isPresented: $dialogs.showRemoteCleanupConfirmation) {
                Button("Delete Remote", role: .destructive, action: onRemoteCleanupDelete)
                Button("Cancel", role: .cancel, action: onRemoteCleanupCancel)
            } message: {
                Text("This permanently removes '\(dialogs.featureBranchName)' from the remote. Other collaborators may be affected, and this cannot be undone.")
            }
    }
}

extension View {
    // swiftlint:disable:next function_parameter_count
    func confirmationDialogs(
        dialogs: MainMenuBranchDialogs,
        showDeleteConfirmation: Binding<Bool>,
        showVisibilityConfirmation: Binding<Bool>,
        showDiscardConfirmation: Binding<Bool>,
        showDiscardAllConfirmation: Binding<Bool>,
        showRestartConfirmation: Binding<Bool>,
        isDeleting: Bool,
        isTogglingVisibility: Bool,
        visibilityConfirmationTitle: String,
        visibilityActionTitle: String,
        visibilityConfirmationMessage: String,
        deleteBranchWarningMessage: String,
        onDeleteRepository: @escaping () -> Void,
        onToggleVisibility: @escaping () -> Void,
        onDiscardConfirm: @escaping () -> Void,
        onDiscardAll: @escaping () -> Void,
        onRestart: @escaping () -> Void,
        onMerge: @escaping () -> Void,
        onCancelMerge: @escaping () -> Void,
        onDirtySwitch: @escaping () -> Void,
        onCancelDirtySwitch: @escaping () -> Void,
        onDeleteBranch: @escaping () -> Void,
        onCancelDeleteBranch: @escaping () -> Void,
        onMergeToDefault: @escaping () -> Void,
        onCancelMergeToDefault: @escaping () -> Void,
        onMergeCleanupDeleteLocal: @escaping () -> Void,
        onMergeCleanupDeleteLocalAndRemote: @escaping () -> Void,
        onMergeCleanupDeleteRemoteOnly: @escaping () -> Void,
        onMergeCleanupKeep: @escaping () -> Void,
        onRemoteCleanupDelete: @escaping () -> Void,
        onRemoteCleanupCancel: @escaping () -> Void
    ) -> some View {
        modifier(ConfirmationDialogsModifier(
            dialogs: dialogs,
            showDeleteConfirmation: showDeleteConfirmation,
            showVisibilityConfirmation: showVisibilityConfirmation,
            showDiscardConfirmation: showDiscardConfirmation,
            showDiscardAllConfirmation: showDiscardAllConfirmation,
            showRestartConfirmation: showRestartConfirmation,
            isDeleting: isDeleting,
            isTogglingVisibility: isTogglingVisibility,
            visibilityConfirmationTitle: visibilityConfirmationTitle,
            visibilityActionTitle: visibilityActionTitle,
            visibilityConfirmationMessage: visibilityConfirmationMessage,
            deleteBranchWarningMessage: deleteBranchWarningMessage,
            onDeleteRepository: onDeleteRepository,
            onToggleVisibility: onToggleVisibility,
            onDiscardConfirm: onDiscardConfirm,
            onDiscardAll: onDiscardAll,
            onRestart: onRestart,
            onMerge: onMerge,
            onCancelMerge: onCancelMerge,
            onDirtySwitch: onDirtySwitch,
            onCancelDirtySwitch: onCancelDirtySwitch,
            onDeleteBranch: onDeleteBranch,
            onCancelDeleteBranch: onCancelDeleteBranch,
            onMergeToDefault: onMergeToDefault,
            onCancelMergeToDefault: onCancelMergeToDefault,
            onMergeCleanupDeleteLocal: onMergeCleanupDeleteLocal,
            onMergeCleanupDeleteLocalAndRemote: onMergeCleanupDeleteLocalAndRemote,
            onMergeCleanupDeleteRemoteOnly: onMergeCleanupDeleteRemoteOnly,
            onMergeCleanupKeep: onMergeCleanupKeep,
            onRemoteCleanupDelete: onRemoteCleanupDelete,
            onRemoteCleanupCancel: onRemoteCleanupCancel
        ))
    }
}
