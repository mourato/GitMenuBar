//
//  MainMenuContent.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    var mainView: some View {
        applyMainViewOverlays(
            to: VStack(spacing: 8) {
                MainMenuHeaderView(
                    currentProjectName: currentProjectName,
                    showProjectSelector: $showProjectSelector,
                    onProjectLongPress: {
                        showRepoOptions = true
                    },
                    onHistoryTap: {
                        showingHistory = true
                        gitManager.fetchCommitHistory()
                    },
                    onSettingsTap: {
                        showingSettings = true
                        UserDefaults.standard.set(true, forKey: "showSettings")
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
                    hasWorkingTreeChanges: hasWorkingTreeChanges,
                    isGenerating: aiCommitCoordinator.isGenerating,
                    isReadyForGeneration: aiCommitCoordinator.isReadyForGeneration,
                    generationDisabledReason: aiCommitCoordinator.generationDisabledReason,
                    generationError: aiCommitCoordinator.generationError,
                    primaryButtonTitle: primaryButtonTitle,
                    isPrimaryButtonDisabled: hasWorkingTreeChanges
                        ? !canCommit
                        : (gitManager.isCommitting || aiCommitCoordinator.isGenerating),
                    onGenerateMessage: {
                        generateCommitMessageFromPriorityScope()
                    },
                    onPrimaryAction: {
                        performPrimaryAction()
                    }
                )
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isCommentFieldFocused = true
                    }
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Staged")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("\(gitManager.stagedFiles.count)")
                                    .font(.system(size: 14, weight: .semibold))
                            }

                            if gitManager.stagedFiles.isEmpty {
                                Text("No staged files")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 2)
                            } else {
                                VStack(spacing: 3) {
                                    ForEach(gitManager.stagedFiles) { file in
                                        WorkingTreeFileRowView(
                                            file: file,
                                            actionIcon: "minus.circle",
                                            actionHelp: "Unstage file",
                                            onAction: { unstageFile(path: file.path) }
                                        )
                                    }
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Changes")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("\(gitManager.changedFiles.count)")
                                    .font(.system(size: 14, weight: .semibold))
                            }

                            if gitManager.changedFiles.isEmpty {
                                Text("No changes")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 2)
                            } else {
                                VStack(spacing: 3) {
                                    ForEach(gitManager.changedFiles) { file in
                                        WorkingTreeFileRowView(
                                            file: file,
                                            actionIcon: "plus.circle",
                                            actionHelp: "Stage file",
                                            onAction: { stageFile(path: file.path) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 210)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .onExitCommand {
                closePopover()
            }
            .onReceive(shortcutActionBridge.actions) { action in
                guard createRepoPath == nil, !showingSettings, !showingHistory else { return }

                switch action {
                case .commit:
                    guard hasWorkingTreeChanges else { return }
                    submitComment()
                case .sync:
                    guard !hasWorkingTreeChanges else { return }
                    syncRepository()
                }
            }
        )
    }
}

#Preview("Main Content") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
