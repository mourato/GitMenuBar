//
//  MainMenuView+MainContent.swift
//  GitMenuBar
//

import AppKit
import KeyboardShortcuts
import SwiftUI

extension MainMenuView {
    var mainView: some View {
        applyMainViewOverlays(
            to: VStack(spacing: 8) {
                // Header
                HStack {
                    Button(action: { showProjectSelector.toggle() }) {
                        HStack(spacing: 4) {
                            Text(currentProjectName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 2.0) {
                        showRepoOptions = true
                    }
                    .onHover { inside in
                        if inside {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .popover(isPresented: $showProjectSelector) {
                        projectSelectorView
                    }

                    Spacer()
                    HStack(spacing: 12) {
                        Button("History") {
                            showingHistory = true
                            gitManager.fetchCommitHistory()
                        }
                        .buttonStyle(.borderless)
                        .focusable(false)

                        Text("|")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.5))

                        Button("Settings") {
                            showingSettings = true
                            UserDefaults.standard.set(true, forKey: "showSettings")
                        }
                        .buttonStyle(.borderless)
                        .focusable(false)
                    }
                }
                .padding(.top, 4)

                Divider()
                    .padding(.top, 4)

                // Branch status - compact with branch selector and remote status
                HStack(spacing: 4) {
                    Button(action: { showBranchSelector.toggle() }) {
                        HStack(spacing: 0) {
                            Text("\(gitManager.currentBranch)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))

                            // Ahead indicator
                            Text(" ▲")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                            Text("\(gitManager.commitCount)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .frame(minWidth: 12, alignment: .leading)

                            // Behind indicator
                            if gitManager.isRemoteAhead {
                                Text(" ▼")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                                Text("\(gitManager.behindCount)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                                    .monospacedDigit()
                                    .frame(minWidth: 12, alignment: .leading)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            gitManager.isDetachedHead ? Color.red.opacity(0.3) :
                                gitManager.isRemoteAhead ? Color.orange.opacity(0.2) :
                                gitManager.commitCount > 0 ? Color.orange.opacity(0.2) :
                                Color.green.opacity(0.2)
                        )
                        .clipShape(Capsule())
                        .animation(nil, value: gitManager.currentBranch)
                        .animation(nil, value: gitManager.commitCount)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .onHover { inside in
                        if inside {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .popover(isPresented: $showBranchSelector) {
                        VStack(alignment: .leading, spacing: 0) {
                            if gitManager.isDetachedHead {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text("Detached HEAD State")
                                            .font(.system(size: 11, weight: .bold))
                                    }

                                    Text("You aren't on a branch. Edits made here might be hard to find later.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Button(action: {
                                        showBranchSelector = false
                                        showCreateBranch = true
                                    }) {
                                        Label("Create Branch from here...", systemImage: "plus.branch")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.accentColor)
                                }
                                .padding(12)
                                .background(Color.red.opacity(0.05))

                                Divider()
                            }

                            Text("Branches")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 6)

                            Divider()
                                .padding(.horizontal, 10)

                            // Quick Pull option when remote is ahead
                            if gitManager.isRemoteAhead {
                                Button(action: {
                                    showBranchSelector = false
                                    useRebase = false // Default to merge for quick pull
                                    syncWithRemote()
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Pull \(gitManager.behindCount) commits")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text("Update current branch from remote")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.orange.opacity(0.1))
                                }
                                .buttonStyle(.plain)
                                .onHover { inside in
                                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }

                                Divider()
                                    .padding(.horizontal, 10)
                            }

                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(gitManager.availableBranches, id: \.self) { branch in
                                        BranchRowView(
                                            branchName: branch,
                                            isCurrentBranch: branch == gitManager.currentBranch,
                                            currentBranchName: gitManager.currentBranch,
                                            onTap: {
                                                showBranchSelector = false
                                                if branch != gitManager.currentBranch {
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
                                                }
                                            },
                                            onMerge: branch != gitManager.currentBranch ? {
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
                                            } : nil,
                                            onDelete: branch != gitManager.currentBranch ? {
                                                showBranchSelector = false
                                                branchNameToDelete = branch
                                                showBranchDeleteConfirmation = true
                                            } : nil,
                                            onRename: {
                                                showBranchSelector = false
                                                oldBranchName = branch
                                                renameBranchNewName = branch
                                                showRenameBranch = true
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(maxHeight: 200)

                            Divider()
                                .padding(.horizontal, 10)

                            NewBranchButton(onTap: {
                                showBranchSelector = false
                                showCreateBranch = true
                            })
                        }
                        .frame(width: 200)
                        .padding(.bottom, 4)
                    }

                    Spacer()
                }

                // Commit message editor with AI generation
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topTrailing) {
                        TextField("Message", text: $commentText, axis: .vertical)
                            .font(.system(size: 13))
                            .lineLimit(1 ... 4)
                            .textFieldStyle(.plain)
                            .padding(.leading, 14)
                            .padding(.trailing, 48)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .focused($isCommentFieldFocused)

                        Button(action: {
                            generateCommitMessageFromPriorityScope()
                        }) {
                            if aiCommitCoordinator.isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .cornerRadius(6)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 7)
                        .padding(.trailing, 8)
                        .disabled(
                            !aiCommitCoordinator.isReadyForGeneration ||
                                aiCommitCoordinator.isGenerating ||
                                !hasWorkingTreeChanges
                        )
                        .help(
                            aiCommitCoordinator.isReadyForGeneration
                                ? "Generate commit message from staged files, or changes when nothing is staged."
                                : aiCommitCoordinator.generationDisabledReason
                        )
                    }

                    Button(primaryButtonTitle) {
                        performPrimaryAction()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(
                        hasWorkingTreeChanges
                            ? !canCommit
                            : (gitManager.isCommitting || aiCommitCoordinator.isGenerating)
                    )
                    .buttonStyle(.borderedProminent)

                    if !aiCommitCoordinator.isReadyForGeneration {
                        Text(aiCommitCoordinator.generationDisabledReason)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else if let generationError = aiCommitCoordinator.generationError {
                        Text(generationError)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isCommentFieldFocused = true
                    }
                }

                Divider()

                // Split working tree sections.
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
                    branchPillView
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

    var projectSelectorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(recentPaths, id: \.self) { path in
                Button(action: {
                    showProjectSelector = false
                    switchRepository(path: path)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: path == currentRepoPath ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundColor(path == currentRepoPath ? .green : .secondary)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button(action: {
                showProjectSelector = false
                selectDirectory()
            }) {
                Label("Browse...", systemImage: "folder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 250)
    }

    var branchPillView: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .medium))
            Text(gitManager.currentBranch)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.08))
        .clipShape(Capsule())
    }
}
