//
//  MainMenuContent.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    private var hasStagedFiles: Bool {
        !gitManager.stagedFiles.isEmpty
    }

    private var hasUnstagedFiles: Bool {
        !gitManager.changedFiles.isEmpty
    }

    private var showsWorkingTreeSections: Bool {
        hasStagedFiles || hasUnstagedFiles
    }

    private var stagedSummary: WorkingTreeSectionSummary {
        gitManager.stagedFiles.sectionSummary
    }

    private var unstagedSummary: WorkingTreeSectionSummary {
        gitManager.changedFiles.sectionSummary
    }

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

            if presentationModel.isFastLoading, !hasWorkingTreeChanges {
                loadingStateView
            }

            if !currentRepoPath.isEmpty {
                RepositoryOverviewView(
                    overview: renderSnapshot.overview,
                    onSelectSection: { selection in
                        selectedInspectorSelection = selection
                    }
                )
            }

            if showsWorkingTreeSections {
                if hasStagedFiles {
                    WorkingTreeSectionView(
                        title: "Staged",
                        summary: stagedSummary,
                        files: stagedRowAdapters,
                        isCollapsed: $isStagedSectionCollapsed,
                        selectedItemID: selectedMainItemID,
                        onSelect: { selectMainItem($0) },
                        onStageToggle: { unstageFile(path: $0) },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: requestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: unstageAllFiles,
                        onDiscardAll: nil,
                        actionIcon: "minus.circle",
                        actionHelp: "Unstage all files"
                    )
                }
                if hasUnstagedFiles {
                    WorkingTreeSectionView(
                        title: "Unstaged",
                        summary: unstagedSummary,
                        files: unstagedRowAdapters,
                        isCollapsed: $isUnstagedSectionCollapsed,
                        selectedItemID: selectedMainItemID,
                        onSelect: { selectMainItem($0) },
                        onStageToggle: { stageFile(path: $0) },
                        onOpen: { gitManager.openFile(path: $0) },
                        onDiscard: requestDiscard,
                        onReveal: { gitManager.revealInFinder(path: $0) },
                        onAction: stageAllFiles,
                        onDiscardAll: {
                            showDiscardAllConfirmation = true
                        },
                        actionIcon: "plus.circle",
                        actionHelp: "Stage all files"
                    )
                }
                Divider()
                    .padding(.top, 2)
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
            onBranchTap: toggleBranchSelectorPresentation,
            onManage: {
                dismissTransientPresentations()
                showBranchManagement = true
            }
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
            CommitWorkflowView(
                commentText: $commentText,
                isCommentFieldFocused: $isCommentFieldFocused,
                showsCommentField: showsCommentField,
                primaryButtonSystemImage: primaryButtonSystemImage,
                isPrimaryActionBusy: isPrimaryActionBusy,
                automaticMessageHint: automaticMessageHint,
                generationDisabledReason: shouldShowGenerationHint ? aiCommitCoordinator.generationDisabledReason : nil,
                generationError: displayedGenerationError,
                automaticRetryAvailable: aiCommitCoordinator.automaticRetryAvailable,
                isFallbackModelAvailable: aiCommitCoordinator.isReadyForFallbackGeneration,
                primaryButtonTitle: primaryButtonTitle,
                isPrimaryButtonDisabled: isPrimaryButtonDisabled,
                canShowSplitCommits: canShowAtomicCommits,
                onPrimaryAction: {
                    Task {
                        await performPrimaryAction()
                    }
                },
                onSplitCommits: startAtomicCommitFlow,
                onRetryGeneration: retryAutomaticGeneration,
                onUseFallbackModel: commitUsingFallbackModel,
                onDidCommit: {
                    if hideCommitMessageField {
                        isCommitFieldTemporarilyVisible = false
                    }
                },
                onRequestFocus: requestCommitFieldFocus,
                focusCommitFieldToken: presentationModel.focusCommitFieldToken,
                actionCoordinator: actionCoordinator,
                commitHistoryEditCoordinator: commitHistoryEditCoordinator
            )

            ScrollView(.vertical) {
                mainScrollContent
            }
            .scrollDisabled(isCommandPalettePresented)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
            .refreshable {
                await gitManager.refreshSelectedRepositoryAsync(includeReflogHistory: false)
            }

            if presentationModel.isFastLoading {
                branchLoadingStateView
            } else {
                footerSection
            }
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let selection = selectedInspectorSelection {
            inspectorView(selection: selection)
        }
    }

    private func inspectorView(selection: MainMenuInspectorSelection) -> some View {
        MainMenuInspectorView(
            projectName: renderSnapshot.currentProjectName,
            selection: selection,
            overview: renderSnapshot.overview,
            historySections: historyTimelineSections,
            historySelectedItemID: selectedMainItemID,
            isHistoryLoading: presentationModel.isDetailLoading,
            canLoadMoreHistory: gitManager.canLoadMoreCommitHistory,
            animationNamespace: animationNamespace,
            isCommitInFuture: isCommitInFuture,
            onClose: clearInspectorSelection,
            onManageBranches: {
                dismissTransientPresentations()
                showBranchManagement = true
            },
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
                        _ = await actionCoordinator.switchInspectorBranch(branch)
                    }
                }
            },
            onSelectHistoryRow: { row in
                selectMainItem(row.id)
            },
            onOpenHistoryCommit: { commitID in
                selectedInspectorSelection = .commit(id: commitID)
                selectedMainItemID = .historyCommit(id: commitID)
            },
            onBackToHistory: {
                selectedInspectorSelection = .history
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
            onLoadMoreHistory: {
                gitManager.loadMoreCommitHistory(batchSize: 25)
            }
        )
    }

    private var projectsSidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isProjectsSidebarCollapsed ? .detailOnly : .all },
            set: { isProjectsSidebarCollapsed = $0 == .detailOnly }
        )
    }

    private func inspectorPresentedBinding(isCompact: Bool) -> Binding<Bool> {
        Binding(
            get: { selectedInspectorSelection != nil && !isCompact },
            set: { isPresented in
                guard !isPresented, !isCompact else { return }
                clearInspectorSelection()
            }
        )
    }

    private func compactInspectorSelectionBinding(isCompact: Bool) -> Binding<MainMenuInspectorSelection?> {
        Binding(
            get: { isCompact ? selectedInspectorSelection : nil },
            set: { selection in
                guard isCompact else { return }
                selectedInspectorSelection = selection
            }
        )
    }

    var mainView: some View {
        GeometryReader { geometry in
            let isCompactInspector = WorkbenchMetrics.usesCompactInspector(for: geometry.size.width)

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
                        onFetchAll: projectMonitor.fetchAll
                    )
                    .navigationSplitViewColumnWidth(
                        min: WorkbenchMetrics.projectsMinimumWidth,
                        ideal: 240,
                        max: 360
                    )
                } detail: {
                    routeContent
                        .inspector(isPresented: inspectorPresentedBinding(isCompact: isCompactInspector)) {
                            inspectorContent
                                .inspectorColumnWidth(
                                    min: WorkbenchMetrics.inspectorMinimumWidth,
                                    ideal: WorkbenchMetrics.inspectorMinimumWidth
                                )
                        }
                        .navigationSplitViewColumnWidth(
                            min: WorkbenchMetrics.centralMinimumWidth,
                            ideal: WorkbenchMetrics.centralMinimumWidth
                        )
                        .padding(.top, WorkbenchMetrics.sectionSpacing)
                        .padding(.leading, WorkbenchMetrics.windowPadding)
                        .padding(.trailing, WorkbenchMetrics.windowPadding)
                        .padding(.bottom, WorkbenchMetrics.windowPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .navigationSplitViewStyle(.balanced)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onExitCommand {
                    if selectedInspectorSelection != nil {
                        clearInspectorSelection()
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
            .sheet(item: compactInspectorSelectionBinding(isCompact: isCompactInspector)) { selection in
                inspectorView(selection: selection)
                    .frame(minWidth: WorkbenchMetrics.inspectorMinimumWidth)
            }
        }
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
