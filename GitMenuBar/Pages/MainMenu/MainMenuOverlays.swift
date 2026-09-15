import SwiftUI

extension MainMenuView {
    func applyMainViewOverlays(to view: some View) -> some View {
        applySheets(to: view)
    }

    var mainWindowOverlayContent: some View {
        ZStack {
            transientPresentationOverlayContent
            commandPaletteOverlayContent
        }
    }

    var transientPresentationOverlayContent: some View {
        MainMenuTransientOverlay(
            isPresented: presentationModel.route == .main && hasTransientPresentation,
            showsRepositoryOptions: showRepositoryOptionsPopover,
            visibilityStatusDescription: repositoryActionSet.visibilityStatusDescription,
            visibilityActionTitle: repositoryActionSet.visibilityActionTitle,
            quotaSnapshot: presentationModel.quotaInfoSnapshot,
            onToggleVisibility: confirmRepositoryVisibilityAction,
            onDeleteRepository: confirmRepositoryDeleteAction,
            onDismiss: dismissTransientPresentations,
            onRetryQuota: {
                dismissTransientPresentations()
                usageQuotaStore.refresh(reason: .manual)
            }
        )
    }

    var branchSelectorOverlay: some View {
        MainMenuBranchSelectorOverlay(
            isDetachedHead: gitManager.isDetachedHead,
            isRemoteAhead: gitManager.isRemoteAhead,
            behindCount: gitManager.behindCount,
            availableBranches: gitManager.availableBranches,
            currentBranch: gitManager.currentBranch,
            onCreateBranchFromDetached: {
                dismissTransientPresentations()
                showCreateBranch = true
            },
            onQuickPull: {
                dismissTransientPresentations()
                useRebase = false
                syncWithRemote()
            },
            onSelectBranch: { branch in
                dismissTransientPresentations()
                guard branch != gitManager.currentBranch else { return }

                if hasWorkingTreeChanges {
                    pendingSwitchBranch = branch
                    showDirtySwitchConfirmation = true
                } else {
                    gitManager.switchBranch(branchName: branch) { result in
                        if case let .failure(error) = result {
                            errorCenter.branchSwitch = error.localizedDescription
                        }
                    }
                }
            },
            onMergeBranch: { branch in
                dismissTransientPresentations()
                if gitManager.currentBranch == "main" || gitManager.currentBranch == "master" {
                    mergeBranchName = branch
                    mergeTargetBranch = gitManager.currentBranch
                    showMergeConfirmation = true
                } else {
                    gitManager.mergeBranch(fromBranch: branch) { result in
                        if case let .failure(error) = result {
                            errorCenter.merge = error.localizedDescription
                        }
                    }
                }
            },
            onDeleteBranch: { branch in
                dismissTransientPresentations()
                branchNameToDelete = branch
                showBranchDeleteConfirmation = true
            },
            onRenameBranch: { branch in
                dismissTransientPresentations()
                oldBranchName = branch
                renameBranchNewName = branch
                showRenameBranch = true
            },
            onMergeToDefaultBranch: { branch in
                dismissTransientPresentations()
                Task {
                    guard let detectedDefaultBranch = await gitManager.getSelectedDefaultBranchNameAsync() else { return }
                    featureBranchName = branch
                    defaultBranchName = detectedDefaultBranch
                    showMergeToDefaultConfirmation = true
                }
            },
            onNewBranch: {
                dismissTransientPresentations()
                showCreateBranch = true
            }
        )
    }

    var commandPaletteOverlayContent: some View {
        MainMenuCommandPaletteOverlay(
            isPresented: isCommandPalettePresented && presentationModel.route == .main,
            query: $commandPaletteQuery,
            items: commandPaletteVisibleItems,
            selectedItemID: $selectedCommandPaletteItemID,
            onClose: closeCommandPalette,
            onSelectItem: executeCommandPaletteItem
        )
    }

    private func applySheets(to view: some View) -> some View {
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
            .sheet(isPresented: $showAtomicCommitSheet, content: atomicCommitSheet)
    }

    var deleteBranchWarningMessage: String {
        let protectedBranches = ["main", "master", "develop"]
        if gitManager.unmergedIntoDefaultBranches.contains(branchNameToDelete) {
            return "This branch is not merged into the default branch. Git will keep it unless you review its removal in Cleanup."
        }
        if protectedBranches.contains(branchNameToDelete) {
            return "WARNING: '\(branchNameToDelete)' is a primary branch. Deleting it may cause serious issues."
        }

        return "Are you sure you want to delete this branch? This action cannot be undone."
    }
}

#Preview("Main Overlays") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        MainMenuView()
    }
}
