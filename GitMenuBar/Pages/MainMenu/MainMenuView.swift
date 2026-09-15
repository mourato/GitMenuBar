//
//  MainMenuView.swift
//  GitMenuBar
//

import SwiftUI

struct MainMenuView: View {
    @Namespace var animationNamespace
    @State var errorCenter = MainMenuErrorCenter()
    @State var branchDialogs = MainMenuBranchDialogs()
    @State var workspace = MainMenuWorkspaceState()
    @State var repoOptions = MainMenuRepositoryOptionsState()
    @State var sync = MainMenuSyncSheetState()
    @State var repoConfirm = MainMenuRepositoryConfirmations()
    @FocusState var isCommentFieldFocused: Bool
    @FocusState var isMainKeyboardNavigationFocused: Bool
    @EnvironmentObject var gitManager: GitManager
    @EnvironmentObject var githubAuthManager: GitHubAuthManager
    @EnvironmentObject var aiCommitCoordinator: AICommitCoordinator
    @EnvironmentObject var actionCoordinator: MainMenuActionCoordinator
    @EnvironmentObject var commitHistoryEditCoordinator: CommitHistoryEditCoordinator
    @EnvironmentObject var shortcutActionBridge: MainMenuShortcutActionBridge
    @EnvironmentObject var presentationModel: MainMenuPresentationModel
    @EnvironmentObject var projectMonitor: ProjectMonitorStore
    @EnvironmentObject var usageQuotaStore: UsageQuotaStore
    @EnvironmentObject var repositorySelectionCoordinator: RepositorySelectionCoordinator
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    @AppStorage(AppPreferences.Keys.isStagedSectionCollapsed) var isStagedSectionCollapsed = false
    @AppStorage(AppPreferences.Keys.isUnstagedSectionCollapsed) var isUnstagedSectionCollapsed = false
    @AppStorage(AppPreferences.Keys.isProjectsSidebarCollapsed) var isProjectsSidebarCollapsed = false
    @AppStorage(AppPreferences.Keys.hideCommitMessageField) var hideCommitMessageField = false
    @AppStorage(AppPreferences.Keys.commitButtonAction)
    var commitButtonAction = AppPreferences.CommitButtonAction.defaultAction.rawValue
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue
    @State var palette = MainMenuCommandPaletteState()

    // Rename branch states

    // Merge confirmation states

    // Merge-to-default states

    // Switch confirmation states

    // Delete confirmation states

    @State var recentProjectReferences = RecentProjectsStore().recentProjects()
    @State var renderSnapshot = MainMenuRenderSnapshot.empty

    let closeWindow: () -> Void
    let openSettingsWindow: () -> Void
    let setAutoHideSuspended: (Bool) -> Void

    var currentRepositoryPath: String {
        repositorySelectionCoordinator.selectedPath
    }

    init(
        closeWindow: @escaping () -> Void = {},
        openSettingsWindow: @escaping () -> Void = {},
        setAutoHideSuspended: @escaping (Bool) -> Void = { _ in }
    ) {
        self.closeWindow = closeWindow
        self.openSettingsWindow = openSettingsWindow
        self.setAutoHideSuspended = setAutoHideSuspended
    }

    var body: some View {
        VStack(spacing: WorkbenchMetrics.compactSpacing) {
            switch presentationModel.route {
            case let .createRepo(path):
                CreateRepositoryPageView(
                    folderPath: path,
                    onCancel: {
                        presentationModel.showMain(requestCommitFocus: true)
                    },
                    onSuccess: { path in
                        guard actionCoordinator.canSwitchRepository(to: path) else { return }
                        if case .selected = repositorySelectionCoordinator.select(
                            path: path,
                            allowsNonGitSelection: true
                        ) {
                            actionCoordinator.resetForRepositorySwitch()
                        }
                        presentationModel.showMain(requestCommitFocus: true)
                        gitManager.updateRemoteUrl()
                        Task { await gitManager.refreshAsync(includeReflogHistory: false) }
                    }
                )
                .environmentObject(gitManager)
                .environmentObject(githubAuthManager)
                .padding(.horizontal, WorkbenchMetrics.windowPadding)
                .padding(.bottom, WorkbenchMetrics.windowPadding)
                .transition(routeTransition)
            case .main, .projectCleanup:
                mainView
                    .transition(routeTransition)
            }
        }
        .adaptiveMotion()
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.route, usesReducedMotion: reduceMotion),
            value: presentationModel.route
        )
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
            value: palette.isPresented
        )
        .confirmationDialogs(
            dialogs: branchDialogs,
            showDeleteConfirmation: $repoConfirm.showDeleteConfirmation,
            showVisibilityConfirmation: $repoConfirm.showVisibilityConfirmation,
            showDiscardConfirmation: $workspace.showDiscardConfirmation,
            showDiscardAllConfirmation: $workspace.showDiscardAllConfirmation,
            showRestartConfirmation: $repoConfirm.showRestartConfirmation,
            isDeleting: repoConfirm.isDeleting,
            isTogglingVisibility: repoConfirm.isTogglingVisibility,
            visibilityConfirmationTitle: repositoryActionSet.visibilityConfirmationTitle,
            visibilityActionTitle: repositoryActionSet.visibilityActionTitle,
            visibilityConfirmationMessage: repositoryActionSet.visibilityConfirmationMessage,
            deleteBranchWarningMessage: deleteBranchWarningMessage,
            onDeleteRepository: deleteRepository,
            onToggleVisibility: toggleRepoVisibility,
            onDiscardConfirm: {
                if let path = workspace.discardFilePath, let status = workspace.discardFileStatus {
                    Task {
                        _ = await actionCoordinator.discardSidePanelFile(path: path, status: status)
                    }
                }
                workspace.discardFilePath = nil
                workspace.discardFileStatus = nil
            },
            onDiscardAll: {
                gitManager.discardAllUnstagedChanges { result in
                    if case let .failure(error) = result {
                        errorCenter.discard = error.localizedDescription
                    }
                }
            },
            onRestart: restartApplication,
            onMerge: {
                gitManager.mergeBranch(fromBranch: branchDialogs.mergeBranchName) { result in
                    if case let .failure(error) = result {
                        errorCenter.merge = error.localizedDescription
                    }
                }
            },
            onCancelMerge: {
                branchDialogs.mergeBranchName = ""
                branchDialogs.mergeTargetBranch = ""
            },
            onDirtySwitch: {
                let branch = branchDialogs.pendingSwitchBranch
                branchDialogs.pendingSwitchBranch = ""
                guard !branch.isEmpty else { return }
                Task {
                    _ = await actionCoordinator.switchSidePanelBranch(branch)
                }
            },
            onCancelDirtySwitch: {
                branchDialogs.pendingSwitchBranch = ""
            },
            onDeleteBranch: {
                let name = branchDialogs.branchNameToDelete
                branchDialogs.branchNameToDelete = ""
                Task {
                    _ = await actionCoordinator.deleteSidePanelBranch(name)
                }
            },
            onCancelDeleteBranch: {
                branchDialogs.branchNameToDelete = ""
            },
            onMergeToDefault: performMergeToDefault,
            onCancelMergeToDefault: {
                branchDialogs.featureBranchName = ""
                branchDialogs.defaultBranchName = ""
            },
            onMergeCleanupDeleteLocal: { performMergeCleanup(option: .deleteLocal) },
            onMergeCleanupDeleteLocalAndRemote: { requestRemoteCleanupConfirmation(option: .deleteLocalAndRemote) },
            onMergeCleanupDeleteRemoteOnly: { requestRemoteCleanupConfirmation(option: .deleteRemoteOnly) },
            onMergeCleanupKeep: dismissMergeCleanup,
            onRemoteCleanupDelete: {
                if let option = branchDialogs.pendingCleanupOption {
                    performMergeCleanup(option: option)
                }
                branchDialogs.pendingCleanupOption = nil
            },
            onRemoteCleanupCancel: {
                branchDialogs.pendingCleanupOption = nil
            }
        )
        .preferredColorScheme(AppPreferences.AppearanceMode.resolve(rawValue: appearanceMode).preferredColorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            mainWindowOverlayContent
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isMainKeyboardNavigationFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .delete, .deleteForward]) { keyPress in
            handleMainKeyPress(keyPress)
        }
        .onAppear {
            reloadRepositorySelectionSnapshot()
            refreshRenderSnapshot()
            synchronizeMainKeyboardNavigationFocus()
            handleCommandPalettePresentationRequest(presentationModel.showCommandPaletteToken)
            handleRepositoryOptionsPresentationRequest(presentationModel.showRepositoryOptionsToken)
            synchronizeSelectedMainItem()
        }
        .onChange(of: presentationModel.showCommandPaletteToken) { _, token in
            handleCommandPalettePresentationRequest(token)
        }
        .onChange(of: presentationModel.showRepositoryOptionsToken) { _, token in
            handleRepositoryOptionsPresentationRequest(token)
        }
        .onChange(of: repoOptions.showProjectSelector) {
            presentPendingRepositoryOptionsIfPossible()
        }
        .onChange(of: branchDialogs.showBranchSelector) {
            presentPendingRepositoryOptionsIfPossible()
        }
        .onChange(of: palette.isPresented) { _, isPresented in
            if !isPresented {
                presentPendingRepositoryOptionsIfPossible()
            }
        }
        .onChange(of: presentationModel.route) { _, route in
            if route != .main {
                clearSidePanelSelection()
                closeCommandPalette()
                dismissTransientPresentations()
                if workspace.commentText.isEmpty {
                    workspace.isCommitFieldTemporarilyVisible = false
                }
            }
        }
        .onChange(of: mainKeyboardFocusSyncToken) {
            synchronizeMainKeyboardNavigationFocus()
        }
        .onChange(of: workspace.selectedMainItemID) {
            synchronizeMainKeyboardNavigationFocus()
        }
        .onChange(of: hideCommitMessageField) { _, isHidden in
            if !isHidden || workspace.commentText.isEmpty {
                workspace.isCommitFieldTemporarilyVisible = false
            }
        }
        .onChange(of: gitManager.stagedFiles) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.changedFiles) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.commitHistory) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.currentHash) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.remoteUrl) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.availableBranches) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.currentBranch) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.commitCount) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.behindCount) {
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.isDetachedHead) {
            refreshRenderSnapshot()
        }
        .onChange(of: currentRepositoryPath) {
            workspace.selectedMainItemID = nil
            clearSidePanelSelection()
            reloadRepositorySelectionSnapshot()
            refreshRenderSnapshot()
        }
        .onChange(of: recentProjectReferences) {
            refreshRenderSnapshot()
        }
        .onChange(of: isStagedSectionCollapsed) {
            refreshRenderSnapshot()
        }
        .onChange(of: isUnstagedSectionCollapsed) {
            refreshRenderSnapshot()
        }
        .onChange(of: keyboardSelectableItems) {
            synchronizeSelectedMainItem()
            synchronizeMainKeyboardNavigationFocus()
        }
        .onChange(of: projectMonitor.snapshots) {
            refreshRenderSnapshot()
        }
        .onChange(of: workspace.selectedSidePanelSelection) { _, selection in
            Task {
                await actionCoordinator.prepareSidePanelSelection(selection)
            }
        }
    }
}

extension MainMenuView {
    private var routeTransition: AnyTransition {
        MainMenuRouteTransition.transition(for: presentationModel.route, reduceMotion: reduceMotion)
    }
}

#Preview("Main Menu Root") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        MainMenuView()
    }
}
