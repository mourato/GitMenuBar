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
    @Environment(GitManager.self) var gitManager
    @Environment(GitHubAuthManager.self) var githubAuthManager
    @Environment(AICommitCoordinator.self) var aiCommitCoordinator
    @Environment(MainMenuActionCoordinator.self) var actionCoordinator
    @Environment(CommitHistoryEditCoordinator.self) var commitHistoryEditCoordinator
    @Environment(MainMenuShortcutActionBridge.self) var shortcutActionBridge
    @Environment(MainMenuPresentationModel.self) var presentationModel
    @Environment(ProjectMonitorStore.self) var projectMonitor
    @Environment(UsageQuotaStore.self) var usageQuotaStore
    @Environment(RepositorySelectionCoordinator.self) var repositorySelectionCoordinator
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
                MainMenuCreateRepoHost(folderPath: path)
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
        .modifier(BranchConfirmationDialogsModifier(dialogs: branchDialogs, errorCenter: errorCenter))
        .modifier(RepositoryConfirmationDialogsModifier(
            confirmations: repoConfirm,
            workspace: workspace,
            errorCenter: errorCenter,
            repositoryActionSet: repositoryActionSet,
            closeWindow: closeWindow
        ))
        .preferredColorScheme(AppPreferences.AppearanceMode.resolve(rawValue: appearanceMode).preferredColorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            windowOverlayContent
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
            workspace.synchronizeSelectedMainItem(with: keyboardSelectableItems)
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
                workspace.clearSidePanelSelection()
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
            workspace.clearSidePanelSelection()
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
            workspace.synchronizeSelectedMainItem(with: keyboardSelectableItems)
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

    private var windowOverlayContent: some View {
        MainMenuWindowOverlayView(
            isTransientPresented: presentationModel.route == .main && hasTransientPresentation,
            showsRepositoryOptions: repoOptions.showRepositoryOptionsPopover,
            visibilityStatusDescription: repositoryActionSet.visibilityStatusDescription,
            visibilityActionTitle: repositoryActionSet.visibilityActionTitle,
            quotaSnapshot: presentationModel.quotaInfoSnapshot,
            onToggleVisibility: {
                dismissTransientPresentations()
                repoConfirm.showVisibilityConfirmation = true
            },
            onDeleteRepository: {
                dismissTransientPresentations()
                repoConfirm.showDeleteConfirmation = true
            },
            onDismissTransient: dismissTransientPresentations,
            onRetryQuota: {
                dismissTransientPresentations()
                usageQuotaStore.refresh(reason: .manual)
            },
            isCommandPalettePresented: palette.isPresented && presentationModel.route == .main,
            paletteQuery: $palette.query,
            paletteItems: commandPaletteVisibleItems,
            paletteSelectedItemID: $palette.selectedItemID,
            onClosePalette: closeCommandPalette,
            onSelectPaletteItem: executeCommandPaletteItem
        )
    }
}

#Preview("Main Menu Root") {
    MainMenuPreviewHarness(showsTransparentTitlebar: true) {
        MainMenuView()
    }
}
