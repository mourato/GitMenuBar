//
//  MainMenuContent.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    private var footerSection: some View {
        MainMenuFooterSection(
            currentBranch: gitManager.currentBranch,
            commitCount: gitManager.commitCount,
            isRemoteAhead: gitManager.isRemoteAhead,
            behindCount: gitManager.behindCount,
            isDetachedHead: gitManager.isDetachedHead,
            onBranchTap: toggleBranchSelectorPresentation,
            isBranchSelectorPresented: $branchDialogs.showBranchSelector
        ) {
            branchSelectorContent
        }
    }

    private var branchSelectorContent: some View {
        MainMenuBranchSelectorHost(
            isDetachedHead: gitManager.isDetachedHead,
            isRemoteAhead: gitManager.isRemoteAhead,
            behindCount: gitManager.behindCount,
            availableBranches: gitManager.availableBranches,
            currentBranch: gitManager.currentBranch,
            onCreateBranchFromDetached: {
                dismissTransientPresentations()
                branchDialogs.showCreateBranch = true
            },
            onQuickPull: {
                dismissTransientPresentations()
                sync.useRebase = false
                sync.syncWithRemote(using: actionCoordinator)
            },
            onSelectBranch: { branch in
                dismissTransientPresentations()
                guard branch != gitManager.currentBranch else { return }

                if hasWorkingTreeChanges {
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
                dismissTransientPresentations()
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
                dismissTransientPresentations()
                branchDialogs.branchNameToDelete = branch
                branchDialogs.showBranchDeleteConfirmation = true
            },
            onRenameBranch: { branch in
                dismissTransientPresentations()
                branchDialogs.oldBranchName = branch
                branchDialogs.renameBranchNewName = branch
                branchDialogs.showRenameBranch = true
            },
            onMergeToDefaultBranch: { branch in
                dismissTransientPresentations()
                Task {
                    guard let detectedDefaultBranch = await gitManager.getSelectedDefaultBranchNameAsync() else { return }
                    branchDialogs.featureBranchName = branch
                    branchDialogs.defaultBranchName = detectedDefaultBranch
                    branchDialogs.showMergeToDefaultConfirmation = true
                }
            },
            onNewBranch: {
                dismissTransientPresentations()
                branchDialogs.showCreateBranch = true
            }
        )
    }

    @ViewBuilder
    private var routeContent: some View {
        switch presentationModel.route {
        case .main, .createRepo:
            mainRouteContent
        case .projectCleanup:
            ProjectCleanupPage()
        }
    }

    private var mainRouteContent: some View {
        VStack(spacing: WorkbenchMetrics.groupSpacing) {
            ScrollView(.vertical) {
                MainMenuOverviewSection(
                    banner: inlineStatusBanner,
                    onDismissBanner: dismissInlineStatusBanner,
                    suggestionPath: presentationModel.createRepoSuggestionPath,
                    currentRepoPath: currentRepoPath,
                    onCreateRepo: { presentationModel.showCreateRepo(path: $0) },
                    overview: snapshotModel.renderSnapshot.overview,
                    commitActionTitle: resolvedCommitButtonAction.buttonTitle,
                    canCommit: actionCoordinator.canAutoCommit,
                    onCommit: performQuickCommit,
                    canSync: actionCoordinator.canSync,
                    onSync: syncRepository,
                    onSelectSection: { workspace.selectedSidePanelSelection = $0 },
                    history: sidePanelHistory
                )
            }
            .scrollDisabled(palette.isPresented)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
            .refreshable {
                await gitManager.refreshSelectedRepositoryAsync(includeReflogHistory: false)
            }

            footerSection
        }
        .disabled(presentationModel.isFastLoading)
        .accessibilityElement(children: .contain)
        .accessibilityValue(presentationModel.isFastLoading ? "Updating project" : "")
    }

    private var sidePanelContent: some View {
        Group {
            if let selection = workspace.selectedSidePanelSelection {
                MainMenuSidePanelHost(
                    selection: selection,
                    projectName: snapshotModel.renderSnapshot.currentProjectName,
                    overview: snapshotModel.renderSnapshot.overview,
                    history: sidePanelHistory,
                    commitMessage: $workspace.commentText,
                    commitFieldFocus: $isCommentFieldFocused,
                    showsCommitField: showsCommentField,
                    commitPrimaryButtonSystemImage: primaryButtonSystemImage,
                    isCommitActionBusy: isPrimaryActionBusy,
                    commitAutomaticMessageHint: automaticMessageHint,
                    commitGenerationDisabledReason: shouldShowGenerationHint
                        ? aiCommitCoordinator.generationDisabledReason : nil,
                    commitGenerationError: displayedGenerationError,
                    commitAutomaticRetryAvailable: aiCommitCoordinator.automaticRetryAvailable,
                    isCommitFallbackModelAvailable: aiCommitCoordinator.isReadyForFallbackGeneration,
                    commitPrimaryButtonTitle: primaryButtonTitle,
                    isCommitPrimaryButtonDisabled: isPrimaryButtonDisabled,
                    canShowSplitCommits: canShowAtomicCommits,
                    commitFocusToken: presentationModel.focusCommitFieldToken,
                    workspaceSelectedFileID: workspace.selectedMainItemID,
                    onClose: workspace.clearSidePanelSelection,
                    onCommitPrimaryAction: {
                        Task {
                            await performPrimaryAction()
                        }
                    },
                    onSplitCommits: startAtomicCommitFlow,
                    onRetryCommitGeneration: retryAutomaticGeneration,
                    onUseCommitFallbackModel: commitUsingFallbackModel,
                    onCommitDidCommit: {
                        if hideCommitMessageField {
                            workspace.isCommitFieldTemporarilyVisible = false
                        }
                    },
                    onRequestCommitFocus: requestCommitFieldFocus,
                    onSelectWorkspaceFile: { workspace.selectMainItem($0) },
                    onDiscardAllUnstaged: {
                        workspace.showDiscardAllConfirmation = true
                    },
                    onRequestDiscard: workspace.requestDiscard,
                    onRequestDeleteBranch: { name in
                        branchDialogs.branchNameToDelete = name
                        branchDialogs.showBranchDeleteConfirmation = true
                    },
                    onRequestSwitchBranch: { branch in
                        guard branch != gitManager.currentBranch else { return }
                        if hasWorkingTreeChanges {
                            branchDialogs.pendingSwitchBranch = branch
                            branchDialogs.showDirtySwitchConfirmation = true
                        } else {
                            Task {
                                _ = await actionCoordinator.sidePanel.switchSidePanelBranch(branch)
                            }
                        }
                    },
                    onCreateBranch: {
                        dismissTransientPresentations()
                        branchDialogs.showCreateBranch = true
                    },
                    onRenameBranch: { name in
                        dismissTransientPresentations()
                        branchDialogs.oldBranchName = name
                        branchDialogs.renameBranchNewName = name
                        branchDialogs.showRenameBranch = true
                    }
                )
            }
        }
        .padding(.horizontal, WorkbenchMetrics.panelPadding)
        .padding(.top, WorkbenchMetrics.iconHitTarget + WorkbenchMetrics.compactSpacing)
        .padding(.bottom, WorkbenchMetrics.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            workspace.selectedSidePanelSelection.map { "Details for \($0.title)" } ?? "Details"
        )
    }

    private var sidePanelHistory: SidePanelHistoryModel {
        SidePanelHistoryModel(
            sections: historyTimelineSections,
            selectedItemID: workspace.selectedMainItemID,
            isLoading: presentationModel.isDetailLoading,
            canLoadMore: gitManager.canLoadMoreCommitHistory,
            animationNamespace: animationNamespace,
            isCommitInFuture: isCommitInFuture,
            onSelectRow: { workspace.selectMainItem($0.id) },
            onOpenCommit: { commitID in
                workspace.selectedSidePanelSelection = .commit(id: commitID)
                workspace.selectedMainItemID = .historyCommit(id: commitID)
            },
            onBackToHistory: {
                workspace.selectedSidePanelSelection = nil
            },
            onEditCommitMessage: { commit in
                Task {
                    await startManualCommitMessageEdit(for: commit)
                }
            },
            onGenerateCommitMessage: { commit in
                Task {
                    await startAutomaticCommitMessageEdit(for: commit)
                }
            },
            onLoadMore: {
                gitManager.loadMoreCommitHistory(batchSize: 25)
            },
            onOpenLocalFile: { gitManager.openFile(path: $0) }
        )
    }

    private var projectsSidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isProjectsSidebarCollapsed ? .detailOnly : .all },
            set: { isProjectsSidebarCollapsed = $0 == .detailOnly }
        )
    }

    /// Presents the trailing side panel while a contextual selection exists on
    /// the main route. Dismissing clears the selection.
    private var isSidePanelPresented: Binding<Bool> {
        Binding(
            get: {
                presentationModel.route == .main && workspace.selectedSidePanelSelection != nil
            },
            set: { isPresented in
                if !isPresented {
                    workspace.selectedSidePanelSelection = nil
                }
            }
        )
    }

    private var sidePanelDismissesOnOutsideTap: Bool {
        workspace.selectedSidePanelSelection != .workingTree
    }

    var mainView: some View {
        MainMenuShellView(
            currentRepositoryPath: currentRepositoryPath,
            onSelectRepository: switchRepository,
            onReveal: revealProjectInFinder,
            onStopMonitoring: { projectMonitor.remove(path: $0) },
            onRemove: removeProject,
            onRename: renameProject,
            onProjectCleanup: presentationModel.showProjectCleanup,
            onAddProject: selectDirectory,
            onRefreshAll: projectMonitor.refreshAll,
            onFetchAll: projectMonitor.fetchAll,
            onOpenSettings: openSettingsWindow,
            sidebarVisibility: projectsSidebarVisibility,
            detail: { routeContent },
            sidePanelPresented: isSidePanelPresented,
            dismissSidePanelOnOutsideTap: sidePanelDismissesOnOutsideTap,
            sidePanel: { sidePanelContent },
            onExitCommand: handleExitCommand,
            shortcutActions: shortcutActionBridge.actions,
            onShortcutAction: handleShortcutAction
        )
        .modifier(MainMenuSheetsModifier(
            branchDialogs: branchDialogs,
            errorCenter: errorCenter,
            workspace: workspace,
            sync: sync
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleExitCommand() {
        if workspace.selectedSidePanelSelection != nil {
            workspace.clearSidePanelSelection()
            return
        }
        if palette.isPresented {
            closeCommandPalette()
            return
        }
        if branchDialogs.showBranchSelector {
            dismissTransientPresentations()
            return
        }
        if repoOptions.showRepositoryOptionsPopover {
            dismissTransientPresentations()
            return
        }
        if hasTransientPresentation {
            dismissTransientPresentations()
            return
        }
        closeWindow()
    }

    private func handleShortcutAction(_ action: MainMenuShortcutAction) {
        guard presentationModel.route == .main else { return }

        switch action {
        case .commit:
            guard hasWorkingTreeChanges else { return }
            Task {
                await submitComment()
            }
        case .sync:
            Task {
                await actionCoordinator.performSync()
            }
        case .atomicCommits:
            startAtomicCommitFlow()
        }
    }

    private func requestCommitFieldFocus() {
        guard showsCommentField, !palette.isPresented else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard showsCommentField, !palette.isPresented else {
                return
            }
            isCommentFieldFocused = true
        }
    }
}

#Preview("Main Content") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        MainMenuView()
    }
}
