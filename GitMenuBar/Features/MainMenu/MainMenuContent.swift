//
//  MainMenuContent.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
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
                    isPrimaryButtonDisabled: isPrimaryButtonDisabled,
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
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            WorkingTreeSectionHeaderView(
                                title: "Unstaged",
                                summary: unstagedSummary,
                                isCollapsed: $isUnstagedSectionCollapsed,
                                actionIcon: "plus.circle",
                                actionHelp: "Stage all files",
                                showsAction: !gitManager.changedFiles.isEmpty,
                                onAction: stageAllFiles
                            )

                            if !isUnstagedSectionCollapsed {
                                if gitManager.changedFiles.isEmpty {
                                    Text("No unstaged files")
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
                    .padding(.trailing, WorkingTreeLayoutMetrics.trailingContentPadding)
                }
                .frame(maxHeight: 400)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
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
                    return
                }
            }
        )
    }
}

private struct WorkingTreeSectionHeaderView: View {
    let title: String
    let summary: WorkingTreeSectionSummary
    @Binding var isCollapsed: Bool
    let actionIcon: String
    let actionHelp: String
    let showsAction: Bool
    let onAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isCollapsed.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(title)
                        .font(.system(size: 13, weight: .medium))

                    Text(summary.fileCountText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            WorkingTreeLineDiffView(
                addedCount: summary.addedLineCount,
                removedCount: summary.removedLineCount
            )

            Button(action: onAction) {
                Image(systemName: actionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(actionHelp)
            .opacity(isHovered && showsAction ? 1 : 0)
            .allowsHitTesting(isHovered && showsAction)
            .frame(width: WorkingTreeLayoutMetrics.actionWidth)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
        }
    }
}

#Preview("Main Content") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
