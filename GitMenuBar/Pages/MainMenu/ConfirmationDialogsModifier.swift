import SwiftUI

struct ConfirmationDialogsModifier: ViewModifier {
    @Binding var showDeleteConfirmation: Bool
    @Binding var showVisibilityConfirmation: Bool
    @Binding var showDiscardConfirmation: Bool
    @Binding var showDiscardAllConfirmation: Bool
    @Binding var showRestartConfirmation: Bool
    @Binding var showMergeConfirmation: Bool
    @Binding var showDirtySwitchConfirmation: Bool
    @Binding var showBranchDeleteConfirmation: Bool
    @Binding var showMergeToDefaultConfirmation: Bool
    @Binding var showMergeCleanupDialog: Bool
    @Binding var showRemoteCleanupConfirmation: Bool

    let isDeleting: Bool
    let isTogglingVisibility: Bool
    let visibilityConfirmationTitle: String
    let visibilityActionTitle: String
    let visibilityConfirmationMessage: String
    let mergeBranchName: String
    let mergeTargetBranch: String
    let pendingSwitchBranch: String
    let branchNameToDelete: String
    let deleteBranchWarningMessage: String
    let featureBranchName: String
    let defaultBranchName: String
    let pendingCleanupOption: BranchCleanupOption?

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
            .alert("Merge into \(mergeTargetBranch)?", isPresented: $showMergeConfirmation) {
                Button("Merge", action: onMerge)
                Button("Cancel", role: .cancel, action: onCancelMerge)
            } message: {
                Text("This will bring all changes from '\(mergeBranchName)' into your current branch '\(mergeTargetBranch)'.")
            }
            .alert("Uncommitted Changes", isPresented: $showDirtySwitchConfirmation) {
                Button("Switch & Carry Over", action: onDirtySwitch)
                Button("Cancel", role: .cancel, action: onCancelDirtySwitch)
            } message: {
                Text("You have uncommitted changes. They will follow you to '\(pendingSwitchBranch)'.")
            }
            .alert("Delete '\(branchNameToDelete)'?", isPresented: $showBranchDeleteConfirmation) {
                Button("Delete", role: .destructive, action: onDeleteBranch)
                Button("Cancel", role: .cancel, action: onCancelDeleteBranch)
            } message: {
                Text(deleteBranchWarningMessage)
            }
            .alert("Merge '\(featureBranchName)' into \(defaultBranchName)?", isPresented: $showMergeToDefaultConfirmation) {
                Button("Merge", action: onMergeToDefault)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel, action: onCancelMergeToDefault)
            } message: {
                Text("This brings all changes from '\(featureBranchName)' into \(defaultBranchName). Uncommitted changes are stashed and restored. The feature branch is kept so you can clean it up afterwards.")
            }
            .confirmationDialog("Clean up '\(featureBranchName)'?", isPresented: $showMergeCleanupDialog, titleVisibility: .visible) {
                Button("Delete Local Only", role: .destructive, action: onMergeCleanupDeleteLocal)
                Button("Delete Local & Remote", role: .destructive, action: onMergeCleanupDeleteLocalAndRemote)
                Button("Delete Remote Only", role: .destructive, action: onMergeCleanupDeleteRemoteOnly)
                Button("Keep Branch", role: .cancel, action: onMergeCleanupKeep)
            } message: {
                Text("'\(featureBranchName)' is merged into \(defaultBranchName). You can delete the feature branch now or keep it.")
            }
            .alert("Delete remote branch '\(featureBranchName)'?", isPresented: $showRemoteCleanupConfirmation) {
                Button("Delete Remote", role: .destructive, action: onRemoteCleanupDelete)
                Button("Cancel", role: .cancel, action: onRemoteCleanupCancel)
            } message: {
                Text("This permanently removes '\(featureBranchName)' from the remote. Other collaborators may be affected, and this cannot be undone.")
            }
    }
}

extension View {
    func confirmationDialogs(
        showDeleteConfirmation: Binding<Bool>,
        showVisibilityConfirmation: Binding<Bool>,
        showDiscardConfirmation: Binding<Bool>,
        showDiscardAllConfirmation: Binding<Bool>,
        showRestartConfirmation: Binding<Bool>,
        showMergeConfirmation: Binding<Bool>,
        showDirtySwitchConfirmation: Binding<Bool>,
        showBranchDeleteConfirmation: Binding<Bool>,
        showMergeToDefaultConfirmation: Binding<Bool>,
        showMergeCleanupDialog: Binding<Bool>,
        showRemoteCleanupConfirmation: Binding<Bool>,
        isDeleting: Bool,
        isTogglingVisibility: Bool,
        visibilityConfirmationTitle: String,
        visibilityActionTitle: String,
        visibilityConfirmationMessage: String,
        mergeBranchName: String,
        mergeTargetBranch: String,
        pendingSwitchBranch: String,
        branchNameToDelete: String,
        deleteBranchWarningMessage: String,
        featureBranchName: String,
        defaultBranchName: String,
        pendingCleanupOption: BranchCleanupOption?,
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
            showDeleteConfirmation: showDeleteConfirmation,
            showVisibilityConfirmation: showVisibilityConfirmation,
            showDiscardConfirmation: showDiscardConfirmation,
            showDiscardAllConfirmation: showDiscardAllConfirmation,
            showRestartConfirmation: showRestartConfirmation,
            showMergeConfirmation: showMergeConfirmation,
            showDirtySwitchConfirmation: showDirtySwitchConfirmation,
            showBranchDeleteConfirmation: showBranchDeleteConfirmation,
            showMergeToDefaultConfirmation: showMergeToDefaultConfirmation,
            showMergeCleanupDialog: showMergeCleanupDialog,
            showRemoteCleanupConfirmation: showRemoteCleanupConfirmation,
            isDeleting: isDeleting,
            isTogglingVisibility: isTogglingVisibility,
            visibilityConfirmationTitle: visibilityConfirmationTitle,
            visibilityActionTitle: visibilityActionTitle,
            visibilityConfirmationMessage: visibilityConfirmationMessage,
            mergeBranchName: mergeBranchName,
            mergeTargetBranch: mergeTargetBranch,
            pendingSwitchBranch: pendingSwitchBranch,
            branchNameToDelete: branchNameToDelete,
            deleteBranchWarningMessage: deleteBranchWarningMessage,
            featureBranchName: featureBranchName,
            defaultBranchName: defaultBranchName,
            pendingCleanupOption: pendingCleanupOption,
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
