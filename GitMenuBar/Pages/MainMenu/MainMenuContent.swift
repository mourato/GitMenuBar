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
                        selectedInspectorSelection = selection
                    }
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

    private var inspectorContent: some View {
        inspectorSelectionView
            .padding(.horizontal, WorkbenchMetrics.panelPadding)
            .padding(.top, WorkbenchMetrics.iconHitTarget + WorkbenchMetrics.compactSpacing)
            .padding(.bottom, WorkbenchMetrics.panelPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(.container, edges: .top)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(selectedInspectorSelection.map { "Details for \($0.title)" } ?? "Details")
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                let roundedWidth = width.rounded()
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
                      roundedWidth >= WorkbenchMetrics.inspectorMinimumWidth,
                      roundedWidth != CGFloat(inspectorColumnWidth) else { return }

                inspectorColumnWidth = Double(roundedWidth)
                MainWindowPreferences.setInspectorColumnWidth(Double(roundedWidth))
            }
    }

    @ViewBuilder
    private var inspectorSelectionView: some View {
        switch selectedInspectorSelection {
        case .workingTree:
            commitWorkspaceView
        case .history, .commit:
            HistoryInspectorView(
                projectName: renderSnapshot.currentProjectName,
                selection: selectedInspectorSelection,
                history: inspectorHistory
            )
        default:
            InspectorDetailView(
                projectName: renderSnapshot.currentProjectName,
                selection: selectedInspectorSelection,
                overview: renderSnapshot.overview,
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
                }
            )
        }
    }

    private var inspectorHistory: InspectorHistoryModel {
        InspectorHistoryModel(
            sections: historyTimelineSections,
            selectedItemID: selectedMainItemID,
            isLoading: presentationModel.isDetailLoading,
            canLoadMore: gitManager.canLoadMoreCommitHistory,
            animationNamespace: animationNamespace,
            isCommitInFuture: isCommitInFuture,
            onSelectRow: { selectMainItem($0.id) },
            onOpenCommit: { commitID in
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
            onLoadMore: {
                gitManager.loadMoreCommitHistory(batchSize: 25)
            },
            onOpenLocalFile: { gitManager.openFile(path: $0) }
        )
    }

    private var commitWorkspaceView: some View {
        InspectorCommitWorkspaceView(
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
            history: inspectorHistory,
            workspaceSelectedFileID: selectedMainItemID,
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
                    max: WorkbenchMetrics.projectsMinimumWidth
                )
            } detail: {
                routeContent
                    .frame(
                        minWidth: WorkbenchMetrics.centralMinimumWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .padding(.top, WorkbenchMetrics.sectionSpacing)
                    .padding(.leading, WorkbenchMetrics.windowPadding)
                    .padding(.trailing, WorkbenchMetrics.windowPadding)
                    .padding(.bottom, WorkbenchMetrics.windowPadding)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
            }
            .inspector(isPresented: .constant(presentationModel.route == .main)) {
                inspectorContent
                    .inspectorColumnWidth(
                        min: WorkbenchMetrics.inspectorMinimumWidth,
                        ideal: max(
                            WorkbenchMetrics.inspectorMinimumWidth,
                            CGFloat(inspectorColumnWidth)
                        ),
                        max: nil
                    )
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
