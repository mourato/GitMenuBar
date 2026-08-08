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
            historySection
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
    }

    @ViewBuilder
    private var routeContent: some View {
        switch presentationModel.route {
        case .main, .createRepo:
            mainRouteContent
        case let .historyDetail(commitID):
            commitDetailRouteView(commitID: commitID)
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
                primaryButtonTitle: primaryButtonTitle,
                isPrimaryButtonDisabled: isPrimaryButtonDisabled,
                canShowSplitCommits: canShowAtomicCommits,
                onPrimaryAction: {
                    Task {
                        await performPrimaryAction()
                    }
                },
                onSplitCommits: startAtomicCommitFlow,
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

            ScrollView(.vertical, showsIndicators: !isCommandPalettePresented) {
                mainScrollContent
            }
            .scrollDisabled(isCommandPalettePresented)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
            .refreshable {
                await gitManager.refreshAsync(includeReflogHistory: false)
            }

            if presentationModel.isFastLoading {
                branchLoadingStateView
            } else {
                footerSection
            }
        }
    }

    private func commitDetailRouteView(commitID: String) -> some View {
        commitDetailContent(commitID: commitID)
    }

    private func commitDetailContent(commitID: String) -> some View {
        CommitDetailPageView(
            commit: gitManager.commitHistory.first(where: { $0.id == commitID }),
            currentHash: gitManager.currentHash,
            remoteUrl: gitManager.remoteUrl,
            isCommitInFuture: isCommitInFuture,
            animationNamespace: animationNamespace,
            onBack: {
                presentationModel.showMain()
            },
            onRestoreCommit: { commit in
                guard commit.id != gitManager.currentHash else { return }
                gitManager.resetToCommit(commit.id)
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
            onOpenLocalFile: { gitManager.openFile(path: $0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var mainView: some View {
        applyMainViewOverlays(
            to: ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
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

                    VStack(spacing: 0) {
                        routeHeaderContent
                            .padding(.leading, WorkbenchMetrics.windowPadding)
                            .padding(.trailing, WorkbenchMetrics.windowPadding)
                            .frame(height: ProjectsSidebarMetrics.headerHeight)
                            .frame(maxWidth: .infinity, alignment: .center)

                        routeContent
                            .padding(.top, WorkbenchMetrics.sectionSpacing)
                            .padding(.leading, WorkbenchMetrics.windowPadding)
                            .padding(.trailing, WorkbenchMetrics.windowPadding)
                            .padding(.bottom, WorkbenchMetrics.windowPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                windowHeaderLeadingControls
                    .frame(height: ProjectsSidebarMetrics.headerHeight, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
            .workbenchScrollbarStyle()
            .onExitCommand {
                if isCommandPalettePresented {
                    closeCommandPalette()
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
    }

    private var historySection: some View {
        HistorySectionView(
            sections: historyTimelineSections,
            selectedItemID: selectedMainItemID,
            isLoading: presentationModel.isDetailLoading,
            canLoadMore: gitManager.canLoadMoreCommitHistory,
            animationNamespace: animationNamespace,
            onSelectRow: { row in
                selectMainItem(row.id)
            },
            onActivateCommit: { row in
                selectMainItem(row.id)
                presentationModel.showHistoryDetail(commitID: row.commit.id)
            },
            onRestoreCommit: { row in
                guard row.actions.canRestore else { return }
                gitManager.resetToCommit(row.commit.id)
            },
            onEditCommitMessage: { row in
                Task {
                    await startManualCommitMessageEdit(for: row.commit)
                }
            },
            onGenerateCommitMessage: { row in
                Task {
                    await startAutomaticCommitMessageEdit(for: row.commit)
                }
            },
            onLoadMore: {
                gitManager.loadMoreCommitHistory(batchSize: 25)
            },
            isCollapsed: $isHistorySectionCollapsed
        )
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
