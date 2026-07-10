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
        VStack(alignment: .leading, spacing: MacChromeMetrics.groupSpacing) {
            if let inlineStatusBanner {
                InlineStatusBannerView(
                    banner: inlineStatusBanner,
                    onDismiss: dismissInlineStatusBanner
                )
            }

            if let suggestionPath = presentationModel.createRepoSuggestionPath, suggestionPath == currentRepoPath {
                createRepoSuggestionBanner(path: suggestionPath)
            }

            if presentationModel.refreshState.isRefreshing && !hasWorkingTreeChanges {
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
                        onDiscard: { path, status in
                            discardFilePath = path
                            discardFileStatus = status
                            showDiscardConfirmation = true
                        },
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
                        onDiscard: { path, status in
                            discardFilePath = path
                            discardFileStatus = status
                            showDiscardConfirmation = true
                        },
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
            availableBranches: gitManager.availableBranches,
            commitCount: gitManager.commitCount,
            isRemoteAhead: gitManager.isRemoteAhead,
            behindCount: gitManager.behindCount,
            isDetachedHead: gitManager.isDetachedHead,
            canShowAtomicCommits: canShowAtomicCommits,
            onBranchTap: {
                showRepositoryOptionsPopover = false
                showBranchSelector.toggle()
            },
            onSelectBranch: { branch in
                showBranchSelector = false
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
                showBranchSelector = false
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
            onCreateBranchFromDetached: {
                showBranchSelector = false
                showCreateBranch = true
            },
            onQuickPull: {
                showBranchSelector = false
                useRebase = false
                syncWithRemote()
            },
            onDeleteBranch: { branch in
                showBranchSelector = false
                branchNameToDelete = branch
                showBranchDeleteConfirmation = true
            },
            onRenameBranch: { branch in
                showBranchSelector = false
                oldBranchName = branch
                renameBranchNewName = branch
                showRenameBranch = true
            },
            onMergeToDefaultBranch: { branch in
                showBranchSelector = false
                featureBranchName = branch
                defaultBranchName = gitManager.defaultBranchName
                showMergeToDefaultConfirmation = true
            },
            onNewBranch: {
                showBranchSelector = false
                showCreateBranch = true
            },
            onAtomicCommits: startAtomicCommitFlow,
            onManage: {
                showRepositoryOptionsPopover = false
                showBranchManagement = true
            },
            onSettings: {
                showRepositoryOptionsPopover = false
                openSettingsWindow()
            },
            showBranchSelector: $showBranchSelector
        )
    }

    var mainView: some View {
        applyMainViewOverlays(
            to: VStack(spacing: MacChromeMetrics.groupSpacing) {
                MainMenuHeaderView(
                    currentProjectName: currentProjectName,
                    showProjectSelector: $showProjectSelector,
                    showRepositoryOptionsPopover: $showRepositoryOptionsPopover,
                    showsRepositoryOptionsButton: canPresentRepositoryOptions,
                    onShowRepositoryOptions: {
                        requestRepositoryOptionsPopoverPresentation()
                    },
                    animationNamespace: animationNamespace,
                    projectSelectorContent: {
                        ProjectSelectorPopoverView(
                            recentPaths: recentPaths,
                            currentRepoPath: currentRepoPath,
                            onSelectPath: { path in
                                showProjectSelector = false
                                switchRepository(path: path)
                            },
                            onBrowse: {
                                showProjectSelector = false
                                selectDirectory()
                            },
                            onShowRepositoryOptions: canPresentRepositoryOptions ? {
                                requestRepositoryOptionsPopoverPresentation()
                            } : nil
                        )
                        .matchedGeometryEffect(id: "projectSelector", in: animationNamespace)
                    },
                    projectContextMenu: {
                        if canPresentRepositoryOptions {
                            Button("Repository Options…") {
                                requestRepositoryOptionsPopoverPresentation()
                            }
                        } else {
                            EmptyView()
                        }
                    },
                    repositoryOptionsContent: {
                        RepositoryOptionsPopoverView(
                            visibilityStatusDescription: repositoryActionSet.visibilityStatusDescription,
                            visibilityActionTitle: repositoryActionSet.visibilityActionTitle,
                            onToggleVisibility: confirmRepositoryVisibilityAction,
                            onDeleteRepository: confirmRepositoryDeleteAction
                        )
                    }
                )

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
                    onPrimaryAction: {
                        Task {
                            await performPrimaryAction()
                        }
                    },
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
                .frame(maxHeight: 520)
                .frame(maxWidth: .infinity, alignment: .leading)

                footerSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onExitCommand {
                if isCommandPalettePresented {
                    closeCommandPalette()
                    return
                }
                if showRepositoryOptionsPopover {
                    showRepositoryOptionsPopover = false
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
                }
            }
        )
    }

    private var historySection: some View {
        HistorySectionView(
            sections: historyTimelineSections,
            selectedItemID: selectedMainItemID,
            isLoading: presentationModel.refreshState.isRefreshing,
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
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
