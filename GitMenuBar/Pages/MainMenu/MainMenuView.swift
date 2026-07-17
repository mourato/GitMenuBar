//
//  MainMenuView.swift
//  GitMenuBar
//

import SwiftUI

struct MainMenuView: View {
    @Namespace var animationNamespace
    @State var commentText = ""
    @State var showDeleteConfirmation = false
    @State var isDeleting = false
    @State var deleteError: String?
    @State var showProjectSelector = false
    @State var showRepositoryOptionsPopover = false
    @State var pendingRepositoryOptionsPresentation = false
    @State var showVisibilityConfirmation = false
    @State var isTogglingVisibility = false
    @State var toggleVisibilityError: String?
    @FocusState var isCommentFieldFocused: Bool
    @EnvironmentObject var gitManager: GitManager
    @EnvironmentObject var githubAuthManager: GitHubAuthManager
    @EnvironmentObject var aiCommitCoordinator: AICommitCoordinator
    @EnvironmentObject var actionCoordinator: MainMenuActionCoordinator
    @EnvironmentObject var commitHistoryEditCoordinator: CommitHistoryEditCoordinator
    @EnvironmentObject var shortcutActionBridge: MainMenuShortcutActionBridge
    @EnvironmentObject var presentationModel: MainMenuPresentationModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @AppStorage(AppPreferences.Keys.isStagedSectionCollapsed) var isStagedSectionCollapsed = false
    @AppStorage(AppPreferences.Keys.isUnstagedSectionCollapsed) var isUnstagedSectionCollapsed = false
    @AppStorage(AppPreferences.Keys.isHistorySectionCollapsed) var isHistorySectionCollapsed = false
    @AppStorage(AppPreferences.Keys.hideCommitMessageField) var hideCommitMessageField = false
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue
    @State var showBranchSelector = false
    @State var showBranchManagement = false
    @State var showAtomicCommitSheet = false
    @State var isCommitFieldTemporarilyVisible = false
    @State var isCommandPalettePresented = false
    @State var commandPaletteQuery = ""
    @State var selectedCommandPaletteItemID: String?
    @State var selectedMainItemID: MainMenuSelectableItem?
    @State var lastHandledCommandPaletteToken = 0
    @State var lastHandledRepositoryOptionsToken = 0
    @State var mainKeyboardMonitor: Any?
    @State var selectedPushBranch: String = ""
    @State var showPullToNewBranch = false
    @State var pullToNewBranchName = ""
    @State var useRebase = false
    @State var syncError: String?
    @State var showRestartConfirmation = false
    @State var restartError: String?
    @State var branchSwitchError: String?
    @State var showCreateBranch = false
    @State var newBranchName: String = ""
    @State var createBranchError: String?
    @State var mergeError: String?
    @State var deleteBranchError: String?
    @State var pushError: String?

    // Rename branch states
    @State var showRenameBranch = false
    @State var oldBranchName = ""
    @State var renameBranchNewName = ""
    @State var renameBranchError: String?

    // Merge confirmation states
    @State var showMergeConfirmation = false
    @State var mergeBranchName = ""
    @State var mergeTargetBranch = ""

    // Merge-to-default states
    @State var showMergeToDefaultConfirmation = false
    @State var showMergeCleanupDialog = false
    @State var showRemoteCleanupConfirmation = false
    @State var pendingCleanupOption: BranchCleanupOption?
    @State var featureBranchName = ""
    @State var defaultBranchName = ""

    // Switch confirmation states
    @State var showDirtySwitchConfirmation = false
    @State var pendingSwitchBranch = ""

    // Delete confirmation states
    @State var showBranchDeleteConfirmation = false
    @State var branchNameToDelete = ""

    @State var showDiscardConfirmation = false
    @State var discardFilePath: String?
    @State var discardFileStatus: WorkingTreeFileStatus?
    @State var discardError: String?
    @State var showDiscardAllConfirmation = false
    @State var currentRepositoryPath = UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
    @State var recentProjectPaths = RecentProjectsStore().recentPaths()
    @State var renderSnapshot = MainMenuRenderSnapshot.empty

    let closeWindow: () -> Void
    let openSettingsWindow: () -> Void
    let setAutoHideSuspended: (Bool) -> Void

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
        VStack(spacing: 10) {
            switch presentationModel.route {
            case let .createRepo(path):
                CreateRepositoryPageView(
                    folderPath: path,
                    onCancel: {
                        presentationModel.showMain(requestCommitFocus: true)
                    },
                    onSuccess: { path in
                        setCurrentRepositoryPath(path)
                        addToRecents(path)
                        presentationModel.showMain(requestCommitFocus: true)
                        gitManager.updateRemoteUrl()
                        gitManager.refresh(includeReflogHistory: false)
                    }
                )
                .environmentObject(gitManager)
                .environmentObject(githubAuthManager)
                .transition(routeTransition)
            case .main:
                mainView
                    .transition(routeTransition)
            case let .historyDetail(commitID):
                CommitDetailPageView(
                    commit: gitManager.commitHistory.first(where: { $0.id == commitID }),
                    currentHash: gitManager.currentHash,
                    remoteUrl: gitManager.remoteUrl,
                    isCommitInFuture: isCommitInFuture,
                    animationNamespace: animationNamespace,
                    onBack: {
                        presentationModel.showMain()
                    },
                    onRestoreCommit: { commit in
                        guard commit.id != gitManager.currentHash else { return }
                        gitManager.resetToCommit(commit.id)
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
                    }
                )
                .transition(routeTransition)
            }
        }
        .adaptiveMotion()
        .animation(
            MacChromeMotion.adaptive(MacChromeMotion.route, usesReducedMotion: reduceMotion),
            value: presentationModel.route
        )
        .animation(
            MacChromeMotion.adaptive(MacChromeMotion.swap, usesReducedMotion: reduceMotion),
            value: isCommandPalettePresented
        )
        .confirmationDialogs(
            showDeleteConfirmation: $showDeleteConfirmation,
            showVisibilityConfirmation: $showVisibilityConfirmation,
            showDiscardConfirmation: $showDiscardConfirmation,
            showDiscardAllConfirmation: $showDiscardAllConfirmation,
            showRestartConfirmation: $showRestartConfirmation,
            showMergeConfirmation: $showMergeConfirmation,
            showDirtySwitchConfirmation: $showDirtySwitchConfirmation,
            showBranchDeleteConfirmation: $showBranchDeleteConfirmation,
            showMergeToDefaultConfirmation: $showMergeToDefaultConfirmation,
            showMergeCleanupDialog: $showMergeCleanupDialog,
            showRemoteCleanupConfirmation: $showRemoteCleanupConfirmation,
            isDeleting: isDeleting,
            isTogglingVisibility: isTogglingVisibility,
            visibilityConfirmationTitle: repositoryActionSet.visibilityConfirmationTitle,
            visibilityActionTitle: repositoryActionSet.visibilityActionTitle,
            visibilityConfirmationMessage: repositoryActionSet.visibilityConfirmationMessage,
            mergeBranchName: mergeBranchName,
            mergeTargetBranch: mergeTargetBranch,
            pendingSwitchBranch: pendingSwitchBranch,
            branchNameToDelete: branchNameToDelete,
            deleteBranchWarningMessage: deleteBranchWarningMessage,
            featureBranchName: featureBranchName,
            defaultBranchName: defaultBranchName,
            pendingCleanupOption: pendingCleanupOption,
            onDeleteRepository: deleteRepository,
            onToggleVisibility: toggleRepoVisibility,
            onDiscardConfirm: {
                if let path = discardFilePath, let status = discardFileStatus {
                    gitManager.discardFileChanges(path: path, status: status) { result in
                        if case let .failure(error) = result {
                            discardError = error.localizedDescription
                        }
                    }
                }
                discardFilePath = nil
                discardFileStatus = nil
            },
            onDiscardAll: {
                gitManager.discardAllUnstagedChanges { result in
                    if case let .failure(error) = result {
                        discardError = error.localizedDescription
                    }
                }
            },
            onRestart: restartApplication,
            onMerge: {
                gitManager.mergeBranch(fromBranch: mergeBranchName) { result in
                    if case let .failure(error) = result {
                        mergeError = error.localizedDescription
                    }
                }
            },
            onCancelMerge: {
                mergeBranchName = ""
                mergeTargetBranch = ""
            },
            onDirtySwitch: {
                gitManager.switchBranch(branchName: pendingSwitchBranch) { result in
                    if case let .failure(error) = result {
                        branchSwitchError = error.localizedDescription
                    }
                }
                pendingSwitchBranch = ""
            },
            onCancelDirtySwitch: {
                pendingSwitchBranch = ""
            },
            onDeleteBranch: {
                gitManager.deleteBranch(branchName: branchNameToDelete) { result in
                    if case let .failure(error) = result {
                        deleteBranchError = error.localizedDescription
                    }
                }
                branchNameToDelete = ""
            },
            onCancelDeleteBranch: {
                branchNameToDelete = ""
            },
            onMergeToDefault: performMergeToDefault,
            onCancelMergeToDefault: {
                featureBranchName = ""
                defaultBranchName = ""
            },
            onMergeCleanupDeleteLocal: { performMergeCleanup(option: .deleteLocal) },
            onMergeCleanupDeleteLocalAndRemote: { requestRemoteCleanupConfirmation(option: .deleteLocalAndRemote) },
            onMergeCleanupDeleteRemoteOnly: { requestRemoteCleanupConfirmation(option: .deleteRemoteOnly) },
            onMergeCleanupKeep: dismissMergeCleanup,
            onRemoteCleanupDelete: {
                if let option = pendingCleanupOption {
                    performMergeCleanup(option: option)
                }
                pendingCleanupOption = nil
            },
            onRemoteCleanupCancel: {
                pendingCleanupOption = nil
            }
        )
        .preferredColorScheme(AppPreferences.AppearanceMode.resolve(rawValue: appearanceMode).preferredColorScheme)
        .padding(.horizontal, MacChromeMetrics.windowPadding)
        .padding(.bottom, MacChromeMetrics.windowPadding)
        .frame(minWidth: 400, idealWidth: 440, maxWidth: .infinity)
        .onAppear {
            reloadRepositorySelectionSnapshot()
            refreshRenderSnapshot()
            installMainKeyboardMonitor()
            handleCommandPalettePresentationRequest(presentationModel.showCommandPaletteToken)
            handleRepositoryOptionsPresentationRequest(presentationModel.showRepositoryOptionsToken)
            synchronizeSelectedMainItem()
        }
        .onDisappear {
            removeMainKeyboardMonitor()
        }
        .onChange(of: presentationModel.showCommandPaletteToken) { token in
            handleCommandPalettePresentationRequest(token)
        }
        .onChange(of: presentationModel.showRepositoryOptionsToken) { token in
            handleRepositoryOptionsPresentationRequest(token)
        }
        .onChange(of: showProjectSelector) { _ in
            presentPendingRepositoryOptionsIfPossible()
        }
        .onChange(of: showBranchSelector) { _ in
            presentPendingRepositoryOptionsIfPossible()
        }
        .onChange(of: isCommandPalettePresented) { _ in
            presentPendingRepositoryOptionsIfPossible()
        }
        .onChange(of: presentationModel.route) { route in
            if route != .main {
                closeCommandPalette()
                showRepositoryOptionsPopover = false
                pendingRepositoryOptionsPresentation = false
                if commentText.isEmpty {
                    isCommitFieldTemporarilyVisible = false
                }
            }
        }
        .onChange(of: hideCommitMessageField) { isHidden in
            if !isHidden || commentText.isEmpty {
                isCommitFieldTemporarilyVisible = false
            }
        }
        .onChange(of: gitManager.stagedFiles) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.changedFiles) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.commitHistory) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.currentHash) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.remoteUrl) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.availableBranches) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: gitManager.currentBranch) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: currentRepositoryPath) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: recentProjectPaths) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: isStagedSectionCollapsed) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: isUnstagedSectionCollapsed) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: isHistorySectionCollapsed) { _ in
            refreshRenderSnapshot()
        }
        .onChange(of: keyboardSelectableItems) { _ in
            synchronizeSelectedMainItem()
        }
    }
}

extension MainMenuView {
    private var routeTransition: AnyTransition {
        MainMenuRouteTransition.transition(for: presentationModel.route, reduceMotion: reduceMotion)
    }
}

private enum MainMenuRouteTransition {
    static func transition(for route: MainMenuRoute, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        switch route {
        case .main:
            return .opacity
        case .createRepo:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity.combined(with: .move(edge: .bottom))
            )
        case .historyDetail:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .trailing))
            )
        }
    }
}

private extension AppPreferences.AppearanceMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .systemDefault:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

private extension MainMenuView {
    func reloadRepositorySelectionSnapshot() {
        currentRepositoryPath = UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
        recentProjectPaths = RecentProjectsStore().recentPaths()
    }

    func refreshRenderSnapshot() {
        renderSnapshot = MainMenuRenderSnapshot.build(
            stagedFiles: gitManager.stagedFiles,
            changedFiles: gitManager.changedFiles,
            commitHistory: gitManager.commitHistory,
            currentHash: gitManager.currentHash,
            remoteUrl: gitManager.remoteUrl,
            availableBranches: gitManager.availableBranches,
            currentBranch: gitManager.currentBranch,
            isStagedSectionCollapsed: isStagedSectionCollapsed,
            isUnstagedSectionCollapsed: isUnstagedSectionCollapsed,
            isHistorySectionCollapsed: isHistorySectionCollapsed,
            recentPaths: recentProjectPaths,
            currentRepoPath: currentRepositoryPath,
            isCommitInFuture: isCommitInFuture
        )
    }
}

#Preview("Main Menu Root") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
