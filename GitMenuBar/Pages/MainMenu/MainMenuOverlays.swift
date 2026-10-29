import SwiftUI

/// Window-level overlay combining the transient presentation overlay
/// (repository options / quota info) with the command palette overlay.
/// Receives plain values and closures; reads no environment.
struct MainMenuWindowOverlayView: View {
    let isTransientPresented: Bool
    let showsRepositoryOptions: Bool
    let visibilityStatusDescription: String
    let visibilityActionTitle: String
    let quotaSnapshot: UsageQuotaSnapshot?
    let onToggleVisibility: () -> Void
    let onDeleteRepository: () -> Void
    let onDismissTransient: () -> Void
    let onRetryQuota: () -> Void

    let isCommandPalettePresented: Bool
    @Binding var paletteQuery: String
    let paletteItems: [MainMenuCommandPaletteItem]
    @Binding var paletteSelectedItemID: String?
    let onClosePalette: () -> Void
    let onSelectPaletteItem: (MainMenuCommandPaletteItem) -> Void

    var body: some View {
        ZStack {
            MainMenuTransientOverlay(
                isPresented: isTransientPresented,
                showsRepositoryOptions: showsRepositoryOptions,
                visibilityStatusDescription: visibilityStatusDescription,
                visibilityActionTitle: visibilityActionTitle,
                quotaSnapshot: quotaSnapshot,
                onToggleVisibility: onToggleVisibility,
                onDeleteRepository: onDeleteRepository,
                onDismiss: onDismissTransient,
                onRetryQuota: onRetryQuota
            )
            MainMenuCommandPaletteOverlay(
                isPresented: isCommandPalettePresented,
                query: $paletteQuery,
                items: paletteItems,
                selectedItemID: $paletteSelectedItemID,
                onClose: onClosePalette,
                onSelectItem: onSelectPaletteItem
            )
        }
    }
}

/// Branch selector popover wiring. Branch state arrives as plain values;
/// selection, merge, delete, rename, and creation effects arrive as closures.
struct MainMenuBranchSelectorContent: View {
    @Bindable var branchDialogs: MainMenuBranchDialogs
    let errorCenter: MainMenuErrorCenter
    @Bindable var sync: MainMenuSyncSheetState
    let onDismissTransientPresentations: () -> Void

    @Environment(GitManager.self) private var gitManager
    @Environment(MainMenuActionCoordinator.self) private var actionCoordinator

    var body: some View {
        MainMenuBranchSelectorHost(
            isDetachedHead: gitManager.isDetachedHead,
            isRemoteAhead: gitManager.isRemoteAhead,
            behindCount: gitManager.behindCount,
            availableBranches: gitManager.availableBranches,
            currentBranch: gitManager.currentBranch,
            onCreateBranchFromDetached: {
                onDismissTransientPresentations()
                branchDialogs.showCreateBranch = true
            },
            onQuickPull: {
                onDismissTransientPresentations()
                sync.useRebase = false
                sync.syncWithRemote(using: actionCoordinator)
            },
            onSelectBranch: { branch in
                onDismissTransientPresentations()
                guard branch != gitManager.currentBranch else { return }

                if !gitManager.stagedFiles.isEmpty || !gitManager.changedFiles.isEmpty {
                    branchDialogs.pendingSwitchBranch = branch
                    branchDialogs.showDirtySwitchConfirmation = true
                } else {
                    gitManager.switchBranch(branchName: branch) { result in
                        if case let .failure(error) = result {
                            errorCenter.branchSwitch = error.localizedDescription
                        }
                    }
                }
            },
            onMergeBranch: { branch in
                onDismissTransientPresentations()
                if gitManager.currentBranch == "main" || gitManager.currentBranch == "master" {
                    branchDialogs.mergeBranchName = branch
                    branchDialogs.mergeTargetBranch = gitManager.currentBranch
                    branchDialogs.showMergeConfirmation = true
                } else {
                    gitManager.mergeBranch(fromBranch: branch) { result in
                        if case let .failure(error) = result {
                            errorCenter.merge = error.localizedDescription
                        }
                    }
                }
            },
            onDeleteBranch: { branch in
                onDismissTransientPresentations()
                branchDialogs.branchNameToDelete = branch
                branchDialogs.showBranchDeleteConfirmation = true
            },
            onRenameBranch: { branch in
                onDismissTransientPresentations()
                branchDialogs.oldBranchName = branch
                branchDialogs.renameBranchNewName = branch
                branchDialogs.showRenameBranch = true
            },
            onMergeToDefaultBranch: { branch in
                onDismissTransientPresentations()
                Task {
                    guard let detectedDefaultBranch = await gitManager.getSelectedDefaultBranchNameAsync() else { return }
                    branchDialogs.featureBranchName = branch
                    branchDialogs.defaultBranchName = detectedDefaultBranch
                    branchDialogs.showMergeToDefaultConfirmation = true
                }
            },
            onNewBranch: {
                onDismissTransientPresentations()
                branchDialogs.showCreateBranch = true
            }
        )
    }
}

struct MainMenuBranchSelectorHost: View {
    let isDetachedHead: Bool
    let isRemoteAhead: Bool
    let behindCount: Int
    let availableBranches: [String]
    let currentBranch: String
    let onCreateBranchFromDetached: () -> Void
    let onQuickPull: () -> Void
    let onSelectBranch: (String) -> Void
    let onMergeBranch: (String) -> Void
    let onDeleteBranch: (String) -> Void
    let onRenameBranch: (String) -> Void
    let onMergeToDefaultBranch: (String) -> Void
    let onNewBranch: () -> Void

    var body: some View {
        MainMenuBranchSelectorOverlay(
            isDetachedHead: isDetachedHead,
            isRemoteAhead: isRemoteAhead,
            behindCount: behindCount,
            availableBranches: availableBranches,
            currentBranch: currentBranch,
            onCreateBranchFromDetached: onCreateBranchFromDetached,
            onQuickPull: onQuickPull,
            onSelectBranch: onSelectBranch,
            onMergeBranch: onMergeBranch,
            onDeleteBranch: onDeleteBranch,
            onRenameBranch: onRenameBranch,
            onMergeToDefaultBranch: onMergeToDefaultBranch,
            onNewBranch: onNewBranch
        )
    }
}

#Preview("Main Overlays") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        MainMenuView()
    }
}
