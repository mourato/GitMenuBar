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
            isBranchSelectorPresented: $showBranchSelector
        ) {
            branchSelectorOverlay
        }
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
                    overview: renderSnapshot.overview,
                    commitActionTitle: resolvedCommitButtonAction.buttonTitle,
                    canCommit: actionCoordinator.canAutoCommit,
                    onCommit: performQuickCommit,
                    canSync: actionCoordinator.canSync,
                    onSync: syncRepository,
                    onSelectSection: { selectedSidePanelSelection = $0 }
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
            if let selection = selectedSidePanelSelection {
                MainMenuSidePanelHost(
                    selection: selection,
                    projectName: renderSnapshot.currentProjectName,
                    overview: renderSnapshot.overview,
                    history: sidePanelHistory,
                    commitMessage: $commentText,
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
                    workspaceSelectedFileID: selectedMainItemID,
                    onClose: clearSidePanelSelection,
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
                            isCommitFieldTemporarilyVisible = false
                        }
                    },
                    onRequestCommitFocus: requestCommitFieldFocus,
                    onSelectWorkspaceFile: { selectMainItem($0) },
                    onDiscardAllUnstaged: {
                        showDiscardAllConfirmation = true
                    },
                    onRequestDiscard: requestDiscard,
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
                                _ = await actionCoordinator.switchSidePanelBranch(branch)
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
            selectedSidePanelSelection.map { "Details for \($0.title)" } ?? "Details"
        )
    }

    private var sidePanelHistory: SidePanelHistoryModel {
        SidePanelHistoryModel(
            sections: historyTimelineSections,
            selectedItemID: selectedMainItemID,
            isLoading: presentationModel.isDetailLoading,
            canLoadMore: gitManager.canLoadMoreCommitHistory,
            animationNamespace: animationNamespace,
            isCommitInFuture: isCommitInFuture,
            onSelectRow: { selectMainItem($0.id) },
            onOpenCommit: { commitID in
                selectedSidePanelSelection = .commit(id: commitID)
                selectedMainItemID = .historyCommit(id: commitID)
            },
            onBackToHistory: {
                selectedSidePanelSelection = .history
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
                presentationModel.route == .main && selectedSidePanelSelection != nil
            },
            set: { isPresented in
                if !isPresented {
                    selectedSidePanelSelection = nil
                }
            }
        )
    }

    private var sidePanelDismissesOnOutsideTap: Bool {
        selectedSidePanelSelection != .workingTree
    }

    var mainView: some View {
        applyMainViewOverlays(
            to: MainMenuShellView(
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
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleExitCommand() {
        if selectedSidePanelSelection != nil {
            clearSidePanelSelection()
            return
        }
        if palette.isPresented {
            closeCommandPalette()
            return
        }
        if showBranchSelector {
            dismissTransientPresentations()
            return
        }
        if showRepositoryOptionsPopover {
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

    private func requestDiscard(path: String, status: WorkingTreeFileStatus) {
        discardFilePath = path
        discardFileStatus = status
        showDiscardConfirmation = true
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
