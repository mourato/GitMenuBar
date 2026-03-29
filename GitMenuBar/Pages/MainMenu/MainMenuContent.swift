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
                    stagedSection
                }
                if hasUnstagedFiles {
                    unstagedSection
                }
                Divider()
                    .padding(.top, 2)
            }
            historySection
        }
    }

    private var footerSection: some View {
        HStack {
            BottomBranchSelectorView(
                currentBranch: gitManager.currentBranch,
                commitCount: gitManager.commitCount,
                isRemoteAhead: gitManager.isRemoteAhead,
                behindCount: gitManager.behindCount,
                isDetachedHead: gitManager.isDetachedHead,
                onTap: {
                    showRepositoryOptionsPopover = false
                    showBranchSelector.toggle()
                }
            )
            .popover(isPresented: $showBranchSelector) {
                BranchSelectorPopoverView(
                    isDetachedHead: gitManager.isDetachedHead,
                    isRemoteAhead: gitManager.isRemoteAhead,
                    behindCount: gitManager.behindCount,
                    availableBranches: gitManager.availableBranches,
                    currentBranch: gitManager.currentBranch,
                    onCreateBranchFromDetached: {
                        showBranchSelector = false
                        showCreateBranch = true
                    },
                    onQuickPull: {
                        showBranchSelector = false
                        useRebase = false
                        syncWithRemote()
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
                    onNewBranch: {
                        showBranchSelector = false
                        showCreateBranch = true
                    }
                )
            }

            Spacer()

            Button("Settings") {
                showRepositoryOptionsPopover = false
                openSettingsWindow()
            }
            .buttonStyle(.borderless)
            .font(MacChromeTypography.detail)
        }
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

                CommitComposerSectionView(
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
                    }
                )
                .onAppear {
                    requestCommitFieldFocus()
                }
                .onChange(of: presentationModel.focusCommitFieldToken) { _ in
                    requestCommitFieldFocus()
                }

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

    private var stagedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkingTreeSectionHeaderView(
                title: "Staged",
                summary: stagedSummary,
                isCollapsed: $isStagedSectionCollapsed,
                actionIcon: "minus.circle",
                actionHelp: "Unstage all files",
                showsAction: !gitManager.stagedFiles.isEmpty,
                onAction: unstageAllFiles
            )

            if !isStagedSectionCollapsed {
                VStack(spacing: 3) {
                    ForEach(stagedRowAdapters) { row in
                        WorkingTreeFileRowView(
                            file: row.file,
                            actionIcon: "minus.circle",
                            actionHelp: row.actions.primaryLabel,
                            isSelected: selectedMainItemID == row.id,
                            onSelect: {
                                selectMainItem(row.id)
                            },
                            onAction: { unstageFile(path: row.file.path) },
                            onOpen: { gitManager.openFile(path: row.file.path) },
                            onDiscard: {
                                selectMainItem(row.id)
                                discardFilePath = row.file.path
                                discardFileStatus = row.file.status
                                showDiscardConfirmation = true
                            },
                            onReveal: { gitManager.revealInFinder(path: row.file.path) }
                        )
                    }
                }
            }
        }
    }

    private var unstagedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            WorkingTreeSectionHeaderView(
                title: "Unstaged",
                summary: unstagedSummary,
                isCollapsed: $isUnstagedSectionCollapsed,
                actionIcon: "plus.circle",
                actionHelp: "Stage all files",
                showsAction: !gitManager.changedFiles.isEmpty,
                onAction: stageAllFiles,
                onDiscardAll: {
                    showDiscardAllConfirmation = true
                }
            )

            if !isUnstagedSectionCollapsed {
                VStack(spacing: 3) {
                    ForEach(unstagedRowAdapters) { row in
                        WorkingTreeFileRowView(
                            file: row.file,
                            actionIcon: "plus.circle",
                            actionHelp: row.actions.primaryLabel,
                            isSelected: selectedMainItemID == row.id,
                            onSelect: {
                                selectMainItem(row.id)
                            },
                            onAction: { stageFile(path: row.file.path) },
                            onOpen: { gitManager.openFile(path: row.file.path) },
                            onDiscard: {
                                selectMainItem(row.id)
                                discardFilePath = row.file.path
                                discardFileStatus = row.file.status
                                showDiscardConfirmation = true
                            },
                            onReveal: { gitManager.revealInFinder(path: row.file.path) }
                        )
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HistorySectionHeaderView(
                commitCount: gitManager.commitHistory.count,
                isCollapsed: $isHistorySectionCollapsed
            )

            if !isHistorySectionCollapsed {
                HistoryTimelineSectionView(
                    sections: historyTimelineSections,
                    selectedItemID: selectedMainItemID,
                    isLoading: presentationModel.refreshState.isRefreshing,
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
                    }
                )

                if gitManager.canLoadMoreCommitHistory {
                    HStack {
                        Spacer()

                        Button("Load 25 more") {
                            gitManager.loadMoreCommitHistory(batchSize: 25)
                        }
                        .buttonStyle(.link)
                        .font(MacChromeTypography.detail)
                        .disabled(presentationModel.refreshState.isRefreshing)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.top, 2)
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
