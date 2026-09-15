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

    @ViewBuilder
    private var transientPresentationOverlayContent: some View {
        if presentationModel.route == .main, hasTransientPresentation {
            ZStack {
                transientPresentationScrim
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .onTapGesture {
                        dismissTransientPresentations()
                    }

                transientPanelContent
            }
            .animation(WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion), value: hasTransientPresentation)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var transientPanelContent: some View {
        if showRepositoryOptionsPopover {
            topCenteredOverlay(repositoryOptionsOverlay)
        } else if let snapshot = presentationModel.quotaInfoSnapshot {
            quotaInfoOverlay(snapshot)
        }
    }

    private func topCenteredOverlay(_ overlay: some View) -> some View {
        HStack {
            Spacer(minLength: 0)
            overlay
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, WorkbenchMetrics.sectionSpacing)
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
    }

    private func quotaInfoOverlay(_ snapshot: UsageQuotaSnapshot) -> some View {
        HStack {
            QuotaStaleInfoPanel(
                snapshot: snapshot,
                onRetry: {
                    dismissTransientPresentations()
                    usageQuotaStore.refresh(reason: .manual)
                }
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, WorkbenchMetrics.windowPadding)
        .padding(.trailing, WorkbenchMetrics.windowPadding)
        .padding(.bottom, WorkbenchMetrics.windowPadding * 2)
        .modifier(TransientPanelChrome(origin: .bottomLeading, reduceMotion: reduceMotion))
    }

    private var repositoryOptionsOverlay: some View {
        RepositoryOptionsPopoverView(
            visibilityStatusDescription: repositoryActionSet.visibilityStatusDescription,
            visibilityActionTitle: repositoryActionSet.visibilityActionTitle,
            onToggleVisibility: confirmRepositoryVisibilityAction,
            onDeleteRepository: confirmRepositoryDeleteAction
        )
        .modifier(TransientPanelChrome(origin: .topCenter, reduceMotion: reduceMotion))
    }

    var branchSelectorOverlay: some View {
        BranchSelectorPopoverView(
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
                            branchSwitchError = error.localizedDescription
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
                            mergeError = error.localizedDescription
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

    @ViewBuilder
    private var transientPresentationScrim: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Color.black.opacity(0.05)
        }
    }

    private struct TransientPanelChrome: ViewModifier {
        let origin: WorkbenchMotion.TransientPanelOrigin
        let reduceMotion: Bool

        func body(content: Content) -> some View {
            content
                .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
                .accessibilityAddTraits(.isModal)
                .transition(WorkbenchMotion.transientPanelTransition(from: origin, usesReducedMotion: reduceMotion))
        }
    }

    @ViewBuilder
    var commandPaletteOverlayContent: some View {
        if isCommandPalettePresented, presentationModel.route == .main {
            ZStack {
                commandPaletteScrim
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
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }
            .transition(.opacity)
        }
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

    @ViewBuilder
    private var commandPaletteScrim: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                Color.black.opacity(0.08)
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
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
