//
//  MainMenuContent.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    private var mainScrollContent: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            if let inlineStatusBanner {
                InlineStatusBannerView(
                    banner: inlineStatusBanner,
                    onDismiss: dismissInlineStatusBanner
                )
            }

            if let suggestionPath = presentationModel.createRepoSuggestionPath, suggestionPath == currentRepoPath {
                createRepoSuggestionBanner(path: suggestionPath)
            }

            if !currentRepoPath.isEmpty {
                RepositoryOverviewView(
                    overview: renderSnapshot.overview,
                    onSelectSection: { selection in
                        selectedSidePanelSelection = selection
                    },
                    commitActionTitle: resolvedCommitButtonAction.buttonTitle,
                    canCommit: actionCoordinator.canAutoCommit,
                    onCommit: performQuickCommit,
                    canSync: actionCoordinator.canSync,
                    onSync: syncRepository
                )
            }
        }
    }

    private var footerSection: some View {
        BranchManagementControlsView(
            currentBranch: gitManager.currentBranch,
            commitCount: gitManager.commitCount,
            isRemoteAhead: gitManager.isRemoteAhead,
            behindCount: gitManager.behindCount,
            isDetachedHead: gitManager.isDetachedHead,
            isBranchSelectorPresented: showBranchSelector,
            onBranchTap: toggleBranchSelectorPresentation
        )
        .popover(isPresented: $showBranchSelector, arrowEdge: .bottom) {
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
                mainScrollContent
            }
            .scrollDisabled(isCommandPalettePresented)
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
        sidePanelSelectionView
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

    @ViewBuilder
    private var sidePanelSelectionView: some View {
        switch selectedSidePanelSelection {
        case .workingTree:
            commitWorkspaceView
        case .history, .commit:
            HistorySidePanelView(
                projectName: renderSnapshot.currentProjectName,
                selection: selectedSidePanelSelection,
                history: sidePanelHistory,
                onClose: clearSidePanelSelection
            )
        default:
            SidePanelDetailView(
                projectName: renderSnapshot.currentProjectName,
                selection: selectedSidePanelSelection,
                overview: renderSnapshot.overview,
                onClose: clearSidePanelSelection,
                onRequestDiscard: requestDiscard,
                onRequestDeleteBranch: { name in
                    branchNameToDelete = name
                    showBranchDeleteConfirmation = true
                },
                onRequestSwitchBranch: { branch in
                    guard branch != gitManager.currentBranch else { return }
                    if hasWorkingTreeChanges {
                        pendingSwitchBranch = branch
                        showDirtySwitchConfirmation = true
                    } else {
                        Task {
                            _ = await actionCoordinator.switchSidePanelBranch(branch)
                        }
                    }
                },
                onCreateBranch: {
                    dismissTransientPresentations()
                    showCreateBranch = true
                },
                onRenameBranch: { name in
                    dismissTransientPresentations()
                    oldBranchName = name
                    renameBranchNewName = name
                    showRenameBranch = true
                }
            )
        }
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

    private var commitWorkspaceView: some View {
        SidePanelCommitWorkspaceView(
            projectName: renderSnapshot.currentProjectName,
            commitMessage: $commentText,
            commitFieldFocus: $isCommentFieldFocused,
            showsCommitField: showsCommentField,
            commitPrimaryButtonSystemImage: primaryButtonSystemImage,
            isCommitActionBusy: isPrimaryActionBusy,
            commitAutomaticMessageHint: automaticMessageHint,
            commitGenerationDisabledReason: shouldShowGenerationHint ? aiCommitCoordinator.generationDisabledReason : nil,
            commitGenerationError: displayedGenerationError,
            commitAutomaticRetryAvailable: aiCommitCoordinator.automaticRetryAvailable,
            isCommitFallbackModelAvailable: aiCommitCoordinator.isReadyForFallbackGeneration,
            commitPrimaryButtonTitle: primaryButtonTitle,
            isCommitPrimaryButtonDisabled: isPrimaryButtonDisabled,
            canShowSplitCommits: canShowAtomicCommits,
            commitFocusToken: presentationModel.focusCommitFieldToken,
            history: sidePanelHistory,
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
            onRequestDiscard: requestDiscard
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
            to: NavigationSplitView(columnVisibility: projectsSidebarVisibility) {
                ProjectsSidebarView(
                    currentPath: currentRepositoryPath,
                    onSelect: switchRepository,
                    onReveal: revealProjectInFinder,
                    onStopMonitoring: { projectMonitor.remove(path: $0) },
                    onRemove: removeProject,
                    onRename: renameProject,
                    onProjectCleanup: presentationModel.showProjectCleanup,
                    onAddProject: selectDirectory,
                    onRefreshAll: projectMonitor.refreshAll,
                    onFetchAll: projectMonitor.fetchAll,
                    onOpenSettings: openSettingsWindow
                )
                .navigationSplitViewColumnWidth(
                    min: WorkbenchMetrics.projectsMinimumWidth,
                    ideal: WorkbenchMetrics.projectsMinimumWidth,
                    max: WorkbenchMetrics.projectsMaximumWidth
                )
            } detail: {
                routeContent
                    .padding(.top, WorkbenchMetrics.sectionSpacing)
                    .padding(.leading, WorkbenchMetrics.windowPadding)
                    .padding(.trailing, WorkbenchMetrics.windowPadding)
                    .padding(.bottom, WorkbenchMetrics.windowPadding)
                    .frame(
                        minWidth: WorkbenchMetrics.centralMinimumWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .sidePanel(
                        isPresented: isSidePanelPresented,
                        dismissOnOutsideTap: sidePanelDismissesOnOutsideTap
                    ) {
                        sidePanelContent
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onExitCommand {
                if selectedSidePanelSelection != nil {
                    clearSidePanelSelection()
                    return
                }
                if isCommandPalettePresented {
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
            .onReceive(shortcutActionBridge.actions) { action in
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
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requestDiscard(path: String, status: WorkingTreeFileStatus) {
        discardFilePath = path
        discardFileStatus = status
        showDiscardConfirmation = true
    }

    private func requestCommitFieldFocus() {
        guard showsCommentField, !isCommandPalettePresented else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard showsCommentField, !isCommandPalettePresented else {
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
