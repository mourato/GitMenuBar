//
//  MainMenuView.swift
//  GitMenuBar
//

import AppKit
import SwiftUI

struct MainMenuView: View {
    @State var commentText = ""
    @State var showDeleteConfirmation = false
    @State var isDeleting = false
    @State var deleteError: String?
    @State var showWipeConfirmation = false
    @State var isWiping = false
    @State var wipeError: String?
    @State var showProjectSelector = false
    @State var showRepoOptions = false
    @State var showVisibilityConfirmation = false
    @State var isTogglingVisibility = false
    @State var toggleVisibilityError: String?
    @FocusState var isCommentFieldFocused: Bool
    @EnvironmentObject var gitManager: GitManager
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var githubAuthManager: GitHubAuthManager
    @EnvironmentObject var aiProviderStore: AIProviderStore
    @EnvironmentObject var aiCommitCoordinator: AICommitCoordinator
    @EnvironmentObject var actionCoordinator: MainMenuActionCoordinator
    @EnvironmentObject var shortcutActionBridge: MainMenuShortcutActionBridge
    @EnvironmentObject var presentationModel: MainMenuPresentationModel
    @AppStorage(AppPreferences.Keys.showFullPathInRecents) var showFullPathInRecents = false
    @AppStorage(AppPreferences.Keys.isStagedSectionCollapsed) var isStagedSectionCollapsed = false
    @AppStorage(AppPreferences.Keys.isUnstagedSectionCollapsed) var isUnstagedSectionCollapsed = false
    @AppStorage(AppPreferences.Keys.isHistorySectionCollapsed) var isHistorySectionCollapsed = false
    @State var showBranchSelector = false
    @State var selectedPushBranch: String = ""
    @State var showPullToNewBranch = false
    @State var pullToNewBranchName = ""
    @State var useRebase = false
    @State var syncError: String?
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

    // Switch confirmation states
    @State var showDirtySwitchConfirmation = false
    @State var pendingSwitchBranch = ""

    // Delete confirmation states
    @State var showBranchDeleteConfirmation = false
    @State var branchNameToDelete = ""

    // Discard confirmation states
    @State var showDiscardConfirmation = false
    @State var discardFilePath: String?
    @State var discardFileStatus: WorkingTreeFileStatus?
    @State var discardError: String?
    @State var showDiscardAllConfirmation = false

    let closeWindow: () -> Void
    let setAutoHideSuspended: (Bool) -> Void

    init(
        closeWindow: @escaping () -> Void = {},
        setAutoHideSuspended: @escaping (Bool) -> Void = { _ in }
    ) {
        self.closeWindow = closeWindow
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
                        gitManager.refresh()
                    }
                )
                .environmentObject(gitManager)
                .environmentObject(githubAuthManager)
            case .settings:
                SettingsPageView(
                    repositoryPath: currentRepoPath,
                    recentPaths: recentPaths,
                    showFullPathInRecents: $showFullPathInRecents,
                    onRepositoryPathChanged: setCurrentRepositoryPath,
                    onBrowse: selectDirectory,
                    onSelectRecentPath: { path in
                        switchRepository(path: path, closeSettingsAfterRefresh: true)
                    },
                    onDone: handleSettingsDone,
                    onSetAutoHideSuspended: setAutoHideSuspended,
                    onWipe: {
                        showWipeConfirmation = true
                    }
                )
            case .main:
                mainView
            case let .historyDetail(commitID):
                CommitDetailPageView(
                    commit: gitManager.commitHistory.first(where: { $0.id == commitID }),
                    currentHash: gitManager.currentHash,
                    remoteUrl: gitManager.remoteUrl,
                    isCommitInFuture: isCommitInFuture,
                    onBack: {
                        presentationModel.showMain()
                    },
                    onRestoreCommit: { commit in
                        guard commit.id != gitManager.currentHash else { return }
                        gitManager.resetToCommit(commit.id)
                    }
                )
            }
        }
        .alert("Delete Repository?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteRepository()
            }
            .disabled(isDeleting)
        } message: {
            Text("This will permanently delete the repository from GitHub. This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: .init(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "An unknown error occurred.")
        }
        .alert(gitManager.isPrivate ? "Make Repository Public?" : "Make Repository Private?", isPresented: $showVisibilityConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(gitManager.isPrivate ? "Make Public" : "Make Private") {
                toggleRepoVisibility()
            }
        } message: {
            Text(
                gitManager.isPrivate ?
                    "Anyone on the internet will be able to see this repository." :
                    "You will choose who can see and commit to this repository."
            )
        }
        .alert("Wipe Repository History?", isPresented: $showWipeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Wipe", role: .destructive) {
                wipeRepository()
            }
            .disabled(isWiping)
        } message: {
            Text(
                "This will permanently erase all commit history and reset the repository to a single 'Initial commit'. Your current files will be preserved. This action cannot be undone."
            )
        }
        .alert("Wipe Failed", isPresented: .init(
            get: { wipeError != nil },
            set: { if !$0 { wipeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wipeError ?? "An unknown error occurred.")
        }
        .confirmationDialog("Repository Options", isPresented: $showRepoOptions) {
            Button(gitManager.isPrivate ? "Make Public" : "Make Private") {
                // Delay to allow menu to dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showVisibilityConfirmation = true
                }
            }
            Button("Delete Repository", role: .destructive) {
                // Delay to allow menu to dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showDeleteConfirmation = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(gitManager.isPrivate ? "This repository is currently private." : "This repository is currently public.")
        }
        .alert("Visibility Update Failed", isPresented: .init(
            get: { toggleVisibilityError != nil },
            set: { if !$0 { toggleVisibilityError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(toggleVisibilityError ?? "An unknown error occurred.")
        }
        .alert("Discard Changes?", isPresented: $showDiscardConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                if let path = discardFilePath, let status = discardFileStatus {
                    gitManager.discardFileChanges(path: path, status: status) { result in
                        if case let .failure(error) = result {
                            discardError = error.localizedDescription
                        }
                    }
                }
            }
        } message: {
            if let path = discardFilePath {
                Text("Are you sure you want to discard changes in '\(path)'? This action cannot be undone.")
            } else {
                Text("Are you sure you want to discard these changes? This action cannot be undone.")
            }
        }
        .alert("Discard All Unstaged Changes?", isPresented: $showDiscardAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Discard All", role: .destructive) {
                gitManager.discardAllUnstagedChanges { result in
                    if case let .failure(error) = result {
                        discardError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Are you sure you want to discard all unstaged changes? This action cannot be undone.")
        }
        .alert("Discard Failed", isPresented: .init(
            get: { discardError != nil },
            set: { if !$0 { discardError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(discardError ?? "An unknown error occurred.")
        }
        .padding(10)
        .frame(width: 400)
    }

    private func handleSettingsDone() {
        if !currentRepoPath.isEmpty {
            addToRecents(currentRepoPath)
            gitManager.refresh()
        }
        presentationModel.showMain(requestCommitFocus: true)
        UserDefaults.standard.set(false, forKey: AppPreferences.Keys.showSettings)
    }
}

#Preview("Main Menu Root") {
    MainMenuPreviewHarness {
        MainMenuView()
    }
}
