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

    var mainView: some View {
        applyMainViewOverlays(
            to: VStack(spacing: 8) {
                MainMenuHeaderView(
                    currentProjectName: currentProjectName,
                    showProjectSelector: $showProjectSelector,
                    onProjectLongPress: {
                        showRepoOptions = true
                    },
                    onSettingsTap: {
                        presentationModel.showSettings()
                        UserDefaults.standard.set(true, forKey: AppPreferences.Keys.showSettings)
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
                            }
                        )
                    }
                )

                Divider()
                    .padding(.top, 4)

                CommitComposerSectionView(
                    commentText: $commentText,
                    isCommentFieldFocused: $isCommentFieldFocused,
                    primaryButtonSystemImage: primaryButtonSystemImage,
                    isPrimaryActionBusy: isPrimaryActionBusy,
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
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
                    .padding(.horizontal, 10)
                }
                .frame(maxHeight: 520)
                .frame(width: 380, alignment: .leading)
                .id(gitManager.stagedFiles.count + gitManager.changedFiles.count)

                HStack {
                    BottomBranchSelectorView(
                        currentBranch: gitManager.currentBranch,
                        commitCount: gitManager.commitCount,
                        isRemoteAhead: gitManager.isRemoteAhead,
                        behindCount: gitManager.behindCount,
                        isDetachedHead: gitManager.isDetachedHead,
                        onTap: {
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
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
            .onExitCommand {
                closePopover()
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
                    ForEach(gitManager.stagedFiles) { file in
                        WorkingTreeFileRowView(
                            file: file,
                            actionIcon: "minus.circle",
                            actionHelp: "Unstage file",
                            onAction: { unstageFile(path: file.path) },
                            onOpen: { gitManager.openFile(path: file.path) },
                            onDiscard: {
                                discardFilePath = file.path
                                discardFileStatus = file.status
                                showDiscardConfirmation = true
                            },
                            onReveal: { gitManager.revealInFinder(path: file.path) }
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
                    ForEach(gitManager.changedFiles) { file in
                        WorkingTreeFileRowView(
                            file: file,
                            actionIcon: "plus.circle",
                            actionHelp: "Stage file",
                            onAction: { stageFile(path: file.path) },
                            onOpen: { gitManager.openFile(path: file.path) },
                            onDiscard: {
                                discardFilePath = file.path
                                discardFileStatus = file.status
                                showDiscardConfirmation = true
                            },
                            onReveal: { gitManager.revealInFinder(path: file.path) }
                        )
                    }
                }
            }
        }
    }

    private var loadingStateView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Loading working tree…")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var historySection: some View {
        HistoryTimelineSectionView(
            commits: gitManager.commitHistory,
            currentHash: gitManager.currentHash,
            remoteUrl: gitManager.remoteUrl,
            isLoading: presentationModel.refreshState.isRefreshing,
            showsHeader: true,
            isCommitInFuture: isCommitInFuture,
            onRestoreCommit: { commit in
                guard commit.id != gitManager.currentHash else { return }
                gitManager.resetToCommit(commit.id)
            }
        )
        .padding(.top, 2)
    }

    private func createRepoSuggestionBanner(path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text("GitHub remote not found for this repository.")
                .font(.system(size: 11))
                .foregroundColor(.primary)

            Spacer()

            Button("Create Repo") {
                presentationModel.showCreateRepo(path: path)
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }

    private func requestCommitFieldFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isCommentFieldFocused = true
        }
    }
}

#Preview("Main Content") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
