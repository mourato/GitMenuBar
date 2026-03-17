//
//  MainMenuComputed.swift
//  GitMenuBar
//

import Foundation

enum MainMenuSyncLabelState: Equatable {
    case none
    case pushOnly
    case syncChanges

    var hasSyncWork: Bool {
        self != .none
    }

    var title: String {
        switch self {
        case .none:
            return ""
        case .pushOnly:
            return "Push Changes"
        case .syncChanges:
            return "Sync Changes"
        }
    }

    static func resolve(hasLocalSyncWork: Bool, hasRemoteSyncWork: Bool) -> MainMenuSyncLabelState {
        if hasLocalSyncWork && !hasRemoteSyncWork {
            return .pushOnly
        }

        if hasLocalSyncWork || hasRemoteSyncWork {
            return .syncChanges
        }

        return .none
    }
}

struct MainMenuPrimaryActionState: Equatable {
    let showsCommitAction: Bool
    let canCommit: Bool
    let canSync: Bool
    let showsIdleCommitState: Bool
    let syncLabelState: MainMenuSyncLabelState

    var isPrimaryButtonDisabled: Bool {
        showsCommitAction ? !canCommit : !canSync
    }

    var primaryButtonTitle: String {
        if showsIdleCommitState {
            return "Nothing to commit"
        }

        if showsCommitAction {
            return "Commit"
        }

        return syncLabelState.title
    }

    var primaryButtonSystemImage: String? {
        if showsIdleCommitState {
            return nil
        }

        if showsCommitAction {
            return "checkmark"
        }

        switch syncLabelState {
        case .pushOnly:
            return "arrow.up"
        case .syncChanges:
            return "arrow.2.circlepath"
        case .none:
            return nil
        }
    }

    static func resolve(
        hasWorkingTreeChanges: Bool,
        hasCommitMessage: Bool,
        syncLabelState: MainMenuSyncLabelState,
        canAutoCommit: Bool,
        isBusy: Bool
    ) -> MainMenuPrimaryActionState {
        let hasSyncWork = syncLabelState.hasSyncWork
        let showsIdleCommitState = !hasWorkingTreeChanges && !hasSyncWork
        let showsCommitAction = hasWorkingTreeChanges || !hasSyncWork
        let canCommit = hasWorkingTreeChanges && (hasCommitMessage || canAutoCommit) && !isBusy
        let canSync = hasSyncWork && !hasWorkingTreeChanges && !isBusy

        return MainMenuPrimaryActionState(
            showsCommitAction: showsCommitAction,
            canCommit: canCommit,
            canSync: canSync,
            showsIdleCommitState: showsIdleCommitState,
            syncLabelState: syncLabelState
        )
    }
}

extension MainMenuView {
    var hasCommitMessage: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var primaryActionState: MainMenuPrimaryActionState {
        MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: hasWorkingTreeChanges,
            hasCommitMessage: hasCommitMessage,
            syncLabelState: syncLabelState,
            canAutoCommit: aiCommitCoordinator.isReadyForGeneration,
            isBusy: isPrimaryActionBusy
        )
    }

    var syncLabelState: MainMenuSyncLabelState {
        MainMenuSyncLabelState.resolve(
            hasLocalSyncWork: gitManager.isAheadOfRemote,
            hasRemoteSyncWork: gitManager.isRemoteAhead
        )
    }

    var recentPaths: [String] {
        RecentProjectsStore().recentPaths()
    }

    var currentRepoPath: String {
        UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
    }

    var currentProjectName: String {
        guard !currentRepoPath.isEmpty else { return "Select Project" }
        return PathDisplayFormatter.projectName(from: currentRepoPath)
    }

    var hasWorkingTreeChanges: Bool {
        !gitManager.stagedFiles.isEmpty || !gitManager.changedFiles.isEmpty
    }

    var canCommit: Bool {
        primaryActionState.canCommit
    }

    var canSync: Bool {
        primaryActionState.canSync
    }

    var showsCommitAction: Bool {
        primaryActionState.showsCommitAction
    }

    var isPrimaryButtonDisabled: Bool {
        primaryActionState.isPrimaryButtonDisabled
    }

    var primaryButtonTitle: String {
        primaryActionState.primaryButtonTitle
    }

    var primaryButtonSystemImage: String? {
        primaryActionState.primaryButtonSystemImage
    }

    var isPrimaryActionBusy: Bool {
        actionCoordinator.isBusy
    }

    var shouldShowGenerationHint: Bool {
        hasWorkingTreeChanges && !hasCommitMessage && !aiCommitCoordinator.isReadyForGeneration
    }

    var displayedGenerationError: String? {
        guard hasWorkingTreeChanges, !hasCommitMessage else { return nil }
        return aiCommitCoordinator.generationError
    }
}
