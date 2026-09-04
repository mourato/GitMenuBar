//
//  MainMenuComputed.swift
//  GitMenuBar
//
// swiftlint:disable file_length

import Foundation

// MARK: - Repository overview model

enum RepositoryMetricState<T: Equatable & Sendable>: Equatable, Sendable {
    case known(T)
    case loading
    case unavailable

    var isLoading: Bool {
        self == .loading
    }
}

struct RepositoryOverviewSnapshot: Equatable, Sendable {
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let addedLineCount: Int
    let removedLineCount: Int
    let aheadCount: RepositoryMetricState<Int>
    let behindCount: RepositoryMetricState<Int>
    let branchesWithoutUpstream: RepositoryMetricState<Int>
    let unpushedBranches: RepositoryMetricState<Int>
    let unmergedBranches: RepositoryMetricState<Int>
    let stashCount: RepositoryMetricState<Int>
    let historyCount: Int
    let currentBranch: String?
    let isDetachedHead: Bool
    let isLoading: Bool
    let lastCheckedAt: Date?

    var totalWorkingTreeCount: Int {
        stagedCount + unstagedCount + untrackedCount
    }

    var isCleanWorkingTree: Bool {
        totalWorkingTreeCount == 0
    }

    // swiftlint:disable:next function_parameter_count
    static func build(
        stagedFiles: [WorkingTreeFile],
        changedFiles: [WorkingTreeFile],
        commitCount: Int,
        aheadOfRemote: Bool,
        behindRemote: Bool,
        gitBehindCount: Int,
        commitHistory: [Commit],
        currentBranch: String,
        isDetachedHead: Bool,
        monitorSnapshot: ProjectStatusSnapshot?,
        isLoading: Bool
    ) -> RepositoryOverviewSnapshot {
        let stagedCount = stagedFiles.count
        let unstagedCount = changedFiles.filter { $0.status != .untracked }.count
        let untrackedCount = changedFiles.filter { $0.status == .untracked }.count
        let workingTreeFiles = stagedFiles + changedFiles
        let addedLineCount = workingTreeFiles.reduce(0) { $0 + $1.lineDiff.added }
        let removedLineCount = workingTreeFiles.reduce(0) { $0 + $1.lineDiff.removed }

        let aheadCount: RepositoryMetricState<Int>
        let behindCount: RepositoryMetricState<Int>
        if let snapshot = monitorSnapshot {
            aheadCount = .known(snapshot.aheadCount)
            behindCount = .known(snapshot.behindCount)
        } else if aheadOfRemote || behindRemote || commitCount > 0 || gitBehindCount > 0 {
            aheadCount = .known(commitCount)
            behindCount = .known(gitBehindCount)
        } else {
            aheadCount = .known(0)
            behindCount = .known(0)
        }

        let branchesWithoutUpstream: RepositoryMetricState<Int>
        let unpushedBranches: RepositoryMetricState<Int>
        let unmergedBranches: RepositoryMetricState<Int>
        let stashCount: RepositoryMetricState<Int>
        if let snapshot = monitorSnapshot {
            branchesWithoutUpstream = .known(snapshot.branchesWithoutUpstreamCount)
            unpushedBranches = .known(snapshot.unpushedBranchCount)
            unmergedBranches = .known(snapshot.unmergedBranchCount)
            stashCount = .known(snapshot.stashCount)
        } else if isLoading {
            branchesWithoutUpstream = .loading
            unpushedBranches = .loading
            unmergedBranches = .loading
            stashCount = .loading
        } else {
            branchesWithoutUpstream = .unavailable
            unpushedBranches = .unavailable
            unmergedBranches = .unavailable
            stashCount = .unavailable
        }

        return RepositoryOverviewSnapshot(
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            addedLineCount: addedLineCount,
            removedLineCount: removedLineCount,
            aheadCount: aheadCount,
            behindCount: behindCount,
            branchesWithoutUpstream: branchesWithoutUpstream,
            unpushedBranches: unpushedBranches,
            unmergedBranches: unmergedBranches,
            stashCount: stashCount,
            historyCount: commitHistory.count,
            currentBranch: currentBranch.isEmpty ? nil : currentBranch,
            isDetachedHead: isDetachedHead,
            isLoading: isLoading,
            lastCheckedAt: monitorSnapshot?.lastRefreshedAt
        )
    }

    nonisolated(unsafe) static let empty = RepositoryOverviewSnapshot(
        stagedCount: 0,
        unstagedCount: 0,
        untrackedCount: 0,
        addedLineCount: 0,
        removedLineCount: 0,
        aheadCount: .known(0),
        behindCount: .known(0),
        branchesWithoutUpstream: .unavailable,
        unpushedBranches: .unavailable,
        unmergedBranches: .unavailable,
        stashCount: .unavailable,
        historyCount: 0,
        currentBranch: nil,
        isDetachedHead: false,
        isLoading: false,
        lastCheckedAt: nil
    )
}

// MARK: - Render snapshot

struct MainMenuRenderSnapshot: Equatable {
    let stagedRowAdapters: [WorkingTreeRowAdapter]
    let unstagedRowAdapters: [WorkingTreeRowAdapter]
    let historyRowAdapters: [HistoryRowAdapter]
    let historySections: [HistoryTimelineSectionModel]
    let keyboardSelectableItems: [MainMenuSelectableItem]
    let branchMenuRows: [BranchMenuRowAdapter]
    let recentProjects: [ProjectReference]
    let currentRepoPath: String
    let currentProjectName: String
    let overview: RepositoryOverviewSnapshot

    static let empty = MainMenuRenderSnapshot(
        stagedRowAdapters: [],
        unstagedRowAdapters: [],
        historyRowAdapters: [],
        historySections: [],
        keyboardSelectableItems: [],
        branchMenuRows: [],
        recentProjects: [],
        currentRepoPath: "",
        currentProjectName: "Select Project",
        overview: .empty
    )

    // Precompute the main menu's expensive derived data from a single snapshot of source state.
    // swiftlint:disable:next function_parameter_count
    static func build(
        stagedFiles: [WorkingTreeFile],
        changedFiles: [WorkingTreeFile],
        commitHistory: [Commit],
        currentHash: String,
        remoteUrl: String,
        availableBranches: [String],
        currentBranch: String,
        isStagedSectionCollapsed: Bool,
        isUnstagedSectionCollapsed: Bool,
        recentProjects: [ProjectReference],
        currentRepoPath: String,
        isCommitInFuture: (Commit) -> Bool,
        overview: RepositoryOverviewSnapshot = .empty
    ) -> MainMenuRenderSnapshot {
        let hasCurrentRepository = !currentRepoPath.isEmpty
        let stagedRowAdapters = hasCurrentRepository ? stagedFiles.map(WorkingTreeRowAdapter.staged(file:)) : []
        let unstagedRowAdapters = hasCurrentRepository ? changedFiles.map(WorkingTreeRowAdapter.unstaged(file:)) : []
        let historyRowAdapters = hasCurrentRepository ? commitHistory.map {
            HistoryRowAdapter(
                commit: $0,
                currentHash: currentHash,
                remoteUrl: remoteUrl,
                isCommitInFuture: isCommitInFuture($0)
            )
        } : []
        let historySections = HistoryTimelineSectionModel.build(from: historyRowAdapters)

        var keyboardSelectableItems: [MainMenuSelectableItem] = []
        if !isStagedSectionCollapsed {
            keyboardSelectableItems += stagedRowAdapters.map(\.id)
        }
        if !isUnstagedSectionCollapsed {
            keyboardSelectableItems += unstagedRowAdapters.map(\.id)
        }

        let normalizedCurrentPath = currentRepoPath.isEmpty ? "" : RecentProjectsStore.normalize(currentRepoPath)
        let storedProjectName = recentProjects.first { $0.path == normalizedCurrentPath }?.name
        let projectName = currentRepoPath.isEmpty
            ? "Select Project"
            : storedProjectName ?? PathDisplayFormatter.defaultProjectName(for: currentRepoPath)
        let branchMenuRows = hasCurrentRepository ? availableBranches.map {
            BranchMenuRowAdapter(branchName: $0, currentBranchName: currentBranch)
        } : []

        return MainMenuRenderSnapshot(
            stagedRowAdapters: stagedRowAdapters,
            unstagedRowAdapters: unstagedRowAdapters,
            historyRowAdapters: historyRowAdapters,
            historySections: historySections,
            keyboardSelectableItems: keyboardSelectableItems,
            branchMenuRows: branchMenuRows,
            recentProjects: recentProjects,
            currentRepoPath: currentRepoPath,
            currentProjectName: projectName,
            overview: overview
        )
    }
}

enum MainMenuInlineBannerSource: Equatable {
    case coordinatorAlert
    case coordinatorSuccess
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
            ""
        case .pushOnly:
            "Push Changes"
        case .syncChanges:
            "Sync Changes"
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
    let commitButtonAction: AppPreferences.CommitButtonAction

    var isPrimaryButtonDisabled: Bool {
        showsCommitAction ? !canCommit : !canSync
    }

    var primaryButtonTitle: String {
        if showsIdleCommitState {
            return "Nothing to commit"
        }

        if showsCommitAction {
            return commitButtonAction.buttonTitle
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
        isBusy: Bool,
        commitButtonAction: AppPreferences.CommitButtonAction = .defaultAction
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
            syncLabelState: syncLabelState,
            commitButtonAction: commitButtonAction
        )
    }
}

extension MainMenuView {
    var historyTimelineSections: [HistoryTimelineSectionModel] {
        renderSnapshot.historySections
    }

    var keyboardSelectableItems: [MainMenuSelectableItem] {
        renderSnapshot.keyboardSelectableItems
    }

    var inlineStatusBannerSource: MainMenuInlineBannerSource? {
        if actionCoordinator.alert != nil {
            return .coordinatorAlert
        }
        if actionCoordinator.success != nil {
            return .coordinatorSuccess
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
        case .coordinatorSuccess:
            guard let success = actionCoordinator.success else { return nil }
            return InlineStatusBanner(title: success.title, message: success.message, style: .info)
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

        return "Automatic commit generation is unavailable. Click \(primaryButtonTitle) to enter a message manually."
    }

    var canCommitWithCurrentInput: Bool {
        hasVisibleCommitMessage || hasWhitespaceOnlyCommitInput || aiCommitCoordinator.isReadyForGeneration || !showsCommentField
    }

    var primaryActionState: MainMenuPrimaryActionState {
        MainMenuPrimaryActionState.resolve(
            hasWorkingTreeChanges: hasWorkingTreeChanges,
            canCommitWithCurrentInput: canCommitWithCurrentInput,
            syncLabelState: syncLabelState,
            isBusy: isPrimaryActionBusy,
            commitButtonAction: resolvedCommitButtonAction
        )
    }

    var resolvedCommitButtonAction: AppPreferences.CommitButtonAction {
        AppPreferences.CommitButtonAction.resolve(rawValue: commitButtonAction)
    }

    var syncLabelState: MainMenuSyncLabelState {
        MainMenuSyncLabelState.resolve(
            hasLocalSyncWork: gitManager.isAheadOfRemote,
            hasRemoteSyncWork: gitManager.isRemoteAhead
        )
    }

    var recentProjects: [ProjectReference] {
        renderSnapshot.recentProjects
    }

    var currentRepoPath: String {
        renderSnapshot.currentRepoPath
    }

    var currentProjectName: String {
        renderSnapshot.currentProjectName
    }

    var repositoryActionSet: RepositoryActionSet {
        RepositoryActionSet(
            currentRepoPath: currentRepoPath,
            remoteUrl: gitManager.remoteUrl,
            isGitHubAuthenticated: githubAuthManager.isAuthenticated,
            isPrivate: gitManager.isPrivate
        )
    }

    var canPresentRepositoryOptions: Bool {
        repositoryActionSet.canShowRepositoryOptions
    }

    var branchMenuRows: [BranchMenuRowAdapter] {
        renderSnapshot.branchMenuRows
    }

    var hasWorkingTreeChanges: Bool {
        !gitManager.stagedFiles.isEmpty || !gitManager.changedFiles.isEmpty
    }

    var canShowAtomicCommits: Bool {
        !gitManager.changedFiles.isEmpty
            && !actionCoordinator.isBusy
            && (aiCommitCoordinator.isReadyForGeneration || resolvedCommitButtonAction == .commitAndPush)
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
            context: AppCommandContext(
                actionState: commandPaletteActionState,
                syncActionTitle: actionCoordinator.syncActionTitle,
                currentRepoPath: currentRepoPath,
                remoteUrl: gitManager.remoteUrl,
                recentProjects: recentProjects,
                isGitHubAuthenticated: githubAuthManager.isAuthenticated,
                hasWorkingTreeChanges: hasWorkingTreeChanges,
                canDoAtomicCommits: canShowAtomicCommits,
                isBehindRemote: gitManager.isBehindRemote,
                isAheadOfRemote: gitManager.isAheadOfRemote,
                canShowBranchManagement: !currentRepoPath.isEmpty,
                currentBranch: gitManager.currentBranch,
                defaultBranchName: gitManager.defaultBranchName,
                monitoredProjects: Array(projectMonitor.snapshots.values)
            )
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
