//
//  MainMenuComputed.swift
//  GitMenuBar
//

import Foundation

enum MainMenuInlineBannerSource: Equatable {
    case coordinatorAlert
    case deleteRepository
    case toggleVisibility
    case discard
    case sync
    case branchSwitch
    case merge
    case deleteBranch
    case renameBranch
    case restart
    case push
}

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
        canCommitWithCurrentInput: Bool,
        syncLabelState: MainMenuSyncLabelState,
        isBusy: Bool
    ) -> MainMenuPrimaryActionState {
        let hasSyncWork = syncLabelState.hasSyncWork
        let showsIdleCommitState = !hasWorkingTreeChanges && !hasSyncWork
        let showsCommitAction = hasWorkingTreeChanges || !hasSyncWork
        let canCommit = hasWorkingTreeChanges && canCommitWithCurrentInput && !isBusy
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
    var inlineStatusBannerSource: MainMenuInlineBannerSource? {
        if actionCoordinator.alert != nil {
            return .coordinatorAlert
        }
        if deleteError != nil {
            return .deleteRepository
        }
        if toggleVisibilityError != nil {
            return .toggleVisibility
        }
        if discardError != nil {
            return .discard
        }
        if syncError != nil {
            return .sync
        }
        if branchSwitchError != nil {
            return .branchSwitch
        }
        if mergeError != nil {
            return .merge
        }
        if deleteBranchError != nil {
            return .deleteBranch
        }
        if renameBranchError != nil {
            return .renameBranch
        }
        if restartError != nil {
            return .restart
        }
        if pushError != nil {
            return .push
        }

        return nil
    }

    var inlineStatusBanner: InlineStatusBanner? {
        switch inlineStatusBannerSource {
        case .coordinatorAlert:
            guard let alert = actionCoordinator.alert else { return nil }
            return InlineStatusBanner(title: alert.title, message: alert.message, style: .error)
        case .deleteRepository:
            return banner(title: "Delete Failed", message: deleteError)
        case .toggleVisibility:
            return banner(title: "Visibility Update Failed", message: toggleVisibilityError)
        case .discard:
            return banner(title: "Discard Failed", message: discardError)
        case .sync:
            return banner(title: "Sync Failed", message: syncError)
        case .branchSwitch:
            return banner(title: "Branch Switch Failed", message: branchSwitchError)
        case .merge:
            return banner(title: "Merge Failed", message: mergeError)
        case .deleteBranch:
            return banner(title: "Delete Failed", message: deleteBranchError)
        case .renameBranch:
            return banner(title: "Rename Failed", message: renameBranchError)
        case .restart:
            return banner(title: "Restart Failed", message: restartError)
        case .push:
            return banner(title: "Push Failed", message: pushError)
        case .none:
            return nil
        }
    }

    var hasVisibleCommitMessage: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasWhitespaceOnlyCommitInput: Bool {
        !commentText.isEmpty && !hasVisibleCommitMessage
    }

    var showsCommentField: Bool {
        !hideCommitMessageField || isCommitFieldTemporarilyVisible
    }

    var automaticMessageHint: String? {
        guard !showsCommentField else {
            return nil
        }

        if aiCommitCoordinator.isReadyForGeneration {
            return "Commit messages will be generated automatically."
        }

        return "Automatic commit generation is unavailable. Click Commit to enter a message manually."
    }

    var canCommitWithCurrentInput: Bool {
        hasVisibleCommitMessage || hasWhitespaceOnlyCommitInput || aiCommitCoordinator.isReadyForGeneration || !showsCommentField
    }

    var primaryActionState: MainMenuPrimaryActionState {
        MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: hasWorkingTreeChanges,
            canCommitWithCurrentInput: canCommitWithCurrentInput,
            syncLabelState: syncLabelState,
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

    var canPresentRepositoryOptions: Bool {
        githubAuthManager.isAuthenticated && !gitManager.remoteUrl.isEmpty
    }

    var hasWorkingTreeChanges: Bool {
        !gitManager.stagedFiles.isEmpty || !gitManager.changedFiles.isEmpty
    }

    var commandPaletteActionState: StatusBarContextMenuActionState {
        StatusBarContextMenuActionState.resolve(
            hasCommitWork: actionCoordinator.hasWorkingTreeChanges,
            hasSyncWork: actionCoordinator.hasSyncWork,
            canAutoCommit: actionCoordinator.canAutoCommit,
            canSync: actionCoordinator.canSync
        )
    }

    var commandPaletteAllItems: [MainMenuCommandPaletteItem] {
        MainMenuCommandPaletteResolver.resolveItems(
            actionState: commandPaletteActionState,
            syncActionTitle: actionCoordinator.syncActionTitle,
            recentPaths: recentPaths,
            currentRepoPath: currentRepoPath
        )
    }

    var commandPaletteVisibleItems: [MainMenuCommandPaletteItem] {
        MainMenuCommandPaletteResolver.filteredItems(
            from: commandPaletteAllItems,
            query: commandPaletteQuery
        )
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
        hasWorkingTreeChanges && !showsCommentField && !aiCommitCoordinator.isReadyForGeneration
    }

    var displayedGenerationError: String? {
        guard hasWorkingTreeChanges, !hasVisibleCommitMessage, !hasWhitespaceOnlyCommitInput else { return nil }
        return aiCommitCoordinator.generationError
    }

    private func banner(title: String, message: String?) -> InlineStatusBanner? {
        guard let message else { return nil }
        return InlineStatusBanner(title: title, message: message, style: .error)
    }
}
