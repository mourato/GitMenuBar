import SwiftUI

extension MainMenuView {
    func applyMainViewOverlays<Content: View>(to view: Content) -> some View {
        applySheets(to: view)
    }

    var mainWindowOverlayContent: some View {
        ZStack {
            transientPresentationOverlayContent
            commandPaletteOverlayContent
        }
    }

    @ViewBuilder
    private var transientPresentationOverlayContent: some View {
        if presentationModel.route == .main && hasTransientPresentation {
            ZStack {
                transientPresentationScrim
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .onTapGesture {
                        dismissTransientPresentations()
                    }

                transientPanelContent
            }
            .animation(WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion), value: hasTransientPresentation)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var transientPanelContent: some View {
        if showRepositoryOptionsPopover {
            topCenteredOverlay(repositoryOptionsOverlay)
        } else if showBranchSelector {
            branchSelectorOverlayLayout
        }
    }

    private func topCenteredOverlay<Overlay: View>(_ overlay: Overlay) -> some View {
        HStack {
            Spacer(minLength: 0)
            overlay
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, WorkbenchMetrics.sectionSpacing)
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
    }

    private var branchSelectorOverlayLayout: some View {
        HStack {
            branchSelectorOverlay
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, mainContentLeadingPadding)
        .padding(.trailing, WorkbenchMetrics.windowPadding)
        .padding(.bottom, WorkbenchMetrics.windowPadding * 2)
    }

    private var mainContentLeadingPadding: CGFloat {
        CGFloat(
            isProjectsSidebarCollapsed
                ? ProjectsSidebarMetrics.collapsedWidth
                : clampedProjectsSidebarWidth
        ) + WorkbenchMetrics.windowPadding
    }

    private var clampedProjectsSidebarWidth: Double {
        min(
            max(projectsSidebarWidth, ProjectsSidebarMetrics.minWidth),
            ProjectsSidebarMetrics.maxWidth
        )
    }

    private var repositoryOptionsOverlay: some View {
        RepositoryOptionsPopoverView(
            visibilityStatusDescription: repositoryActionSet.visibilityStatusDescription,
            visibilityActionTitle: repositoryActionSet.visibilityActionTitle,
            onToggleVisibility: confirmRepositoryVisibilityAction,
            onDeleteRepository: confirmRepositoryDeleteAction
        )
        .modifier(TransientPanelChrome(origin: .topCenter, reduceMotion: reduceMotion))
    }

    private var branchSelectorOverlay: some View {
        BranchSelectorPopoverView(
            isDetachedHead: gitManager.isDetachedHead,
            isRemoteAhead: gitManager.isRemoteAhead,
            behindCount: gitManager.behindCount,
            availableBranches: gitManager.availableBranches,
            currentBranch: gitManager.currentBranch,
            onCreateBranchFromDetached: {
                dismissTransientPresentations()
                showCreateBranch = true
            },
            onQuickPull: {
                dismissTransientPresentations()
                useRebase = false
                syncWithRemote()
            },
            onSelectBranch: { branch in
                dismissTransientPresentations()
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
                dismissTransientPresentations()
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
                dismissTransientPresentations()
                branchNameToDelete = branch
                showBranchDeleteConfirmation = true
            },
            onRenameBranch: { branch in
                dismissTransientPresentations()
                oldBranchName = branch
                renameBranchNewName = branch
                showRenameBranch = true
            },
            onMergeToDefaultBranch: { branch in
                dismissTransientPresentations()
                Task {
                    let detectedDefaultBranch = await gitManager.getDefaultBranchNameAsync()
                    featureBranchName = branch
                    defaultBranchName = detectedDefaultBranch
                    showMergeToDefaultConfirmation = true
                }
            },
            onNewBranch: {
                dismissTransientPresentations()
                showCreateBranch = true
            }
        )
        .modifier(TransientPanelChrome(origin: .bottomLeading, reduceMotion: reduceMotion))
    }

    @ViewBuilder
    private var transientPresentationScrim: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Color.black.opacity(0.05)
        }
    }

    private struct TransientPanelChrome: ViewModifier {
        let origin: WorkbenchMotion.TransientPanelOrigin
        let reduceMotion: Bool

        func body(content: Content) -> some View {
            content
                .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
                .accessibilityAddTraits(.isModal)
                .transition(WorkbenchMotion.transientPanelTransition(from: origin, usesReducedMotion: reduceMotion))
        }
    }

    @ViewBuilder
    var commandPaletteOverlayContent: some View {
        if isCommandPalettePresented && presentationModel.route == .main {
            ZStack {
                commandPaletteScrim
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeCommandPalette()
                    }
                    .zIndex(0)

                MainMenuCommandPaletteView(
                    query: $commandPaletteQuery,
                    items: commandPaletteVisibleItems,
                    selectedItemID: $selectedCommandPaletteItemID,
                    onClose: closeCommandPalette,
                    onSelectItem: executeCommandPaletteItem
                )
                .accessibilityAddTraits(.isModal)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }
            .transition(.opacity)
        }
    }

    private func applySheets<Content: View>(to view: Content) -> some View {
        view
            .sheet(isPresented: $showRenameBranch, content: renameBranchSheet)
            .sheet(
                isPresented: .init(
                    get: { commitHistoryEditCoordinator.isEditorPresented },
                    set: { isPresented in
                        if !isPresented {
                            commitHistoryEditCoordinator.dismissEditor()
                        }
                    }
                )
            ) { commitMessageEditorSheet() }
            .sheet(isPresented: $actionCoordinator.showSyncOptions, content: syncOptionsSheet)
            .sheet(isPresented: $showCreateBranch, content: createBranchSheet)
            .sheet(isPresented: $showPullToNewBranch, content: pullToNewBranchSheet)
            .sheet(isPresented: $showBranchManagement, content: branchManagementSheet)
            .sheet(isPresented: $showAtomicCommitSheet, content: atomicCommitSheet)
    }

    @ViewBuilder
    private var commandPaletteScrim: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                Color.black.opacity(0.08)
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
    }

    var deleteBranchWarningMessage: String {
        let protectedBranches = ["main", "master", "develop"]
        if protectedBranches.contains(branchNameToDelete) {
            return "WARNING: '\(branchNameToDelete)' is a primary branch. Deleting it may cause serious issues."
        }

        return "Are you sure you want to delete this branch? This action cannot be undone."
    }

    private func renameBranchSheet() -> some View {
        RenameBranchSheet(
            oldBranchName: oldBranchName,
            newBranchName: $renameBranchNewName,
            errorMessage: renameBranchError,
            onCancel: {
                showRenameBranch = false
                renameBranchNewName = ""
                renameBranchError = nil
            },
            onRename: renameBranch
        )
    }

    @ViewBuilder
    private func commitMessageEditorSheet() -> some View {
        if let editingCommit = commitHistoryEditCoordinator.editingCommit {
            CommitMessageEditorSheet(
                title: commitHistoryEditCoordinator.editMode.title,
                commit: editingCommit,
                message: $commitHistoryEditCoordinator.draftMessage,
                isPublishedCommit: commitHistoryEditCoordinator.isPublishedCommit,
                isSaving: commitHistoryEditCoordinator.isSaving,
                errorMessage: commitHistoryEditCoordinator.inlineError,
                onCancel: {
                    commitHistoryEditCoordinator.dismissEditor()
                },
                onSave: {
                    Task {
                        await saveEditedCommitMessage()
                    }
                }
            )
        }
    }

    private func syncOptionsSheet() -> some View {
        VStack(spacing: 16) {
            Text("Sync with Remote")
                .font(.headline.weight(.semibold))

            Text(syncOptionsSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                SyncOptionCard(
                    title: "Merge",
                    subtitle: "Safe: Creates a merge commit",
                    tone: .accent
                ) {
                    useRebase = false
                    syncWithRemote()
                }

                SyncOptionCard(
                    title: "Rebase",
                    subtitle: "Clean: Replays your commits on top",
                    tone: .warning
                ) {
                    useRebase = true
                    syncWithRemote()
                }

                SyncOptionCard(
                    title: "Pull to New Branch",
                    subtitle: "Safe: Creates a fresh branch from remote",
                    tone: .success
                ) {
                    actionCoordinator.dismissSyncOptions()
                    pullToNewBranchName = "\(gitManager.currentBranch)-remote"
                    showPullToNewBranch = true
                }
            }

            Button("Cancel") {
                actionCoordinator.dismissSyncOptions()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 320)
    }

    private var syncOptionsSubtitle: String {
        "Remote has \(gitManager.behindCount) new commit\(gitManager.behindCount == 1 ? "" : "s")"
    }

    private func createBranchSheet() -> some View {
        CreateBranchSheet(
            branchName: $newBranchName,
            currentBranch: gitManager.currentBranch,
            errorMessage: createBranchError,
            onCancel: {
                showCreateBranch = false
                newBranchName = ""
                createBranchError = nil
            },
            onCreate: createNewBranch
        )
    }

    private func pullToNewBranchSheet() -> some View {
        PullToNewBranchSheet(
            branchName: $pullToNewBranchName,
            errorMessage: syncError,
            onCancel: {
                showPullToNewBranch = false
                pullToNewBranchName = ""
                syncError = nil
            },
            onPull: pullToNewBranch
        )
    }

    private func branchManagementSheet() -> some View {
        BranchManagementSheet(gitManager: gitManager)
    }

    private func atomicCommitSheet() -> some View {
        AtomicCommitReviewSheet(
            gitManager: gitManager,
            generateGroups: { [weak gitManager, weak aiCommitCoordinator] in
                guard let gitManager,
                      let coordinator = aiCommitCoordinator else {
                    return []
                }
                let changed = gitManager.changedFiles
                let diffs = await gitManager.diffForChangedFilesAsync()
                return try await coordinator.generateAtomicGroups(
                    changedFiles: changed,
                    diffPerFile: diffs
                )
            },
            onCancel: {
                showAtomicCommitSheet = false
            },
            onCommit: { groups in
                showAtomicCommitSheet = false
                Task {
                    _ = await gitManager.performAtomicCommitsAsync(groups: groups)
                }
            }
        )
    }
}

#Preview("Main Overlays") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        MainMenuView()
    }
}
