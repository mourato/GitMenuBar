//
//  MainMenuComputed.swift
//  GitMenuBar
//

import Foundation

struct MainMenuPrimaryActionState: Equatable {
    let showsCommitAction: Bool
    let canCommit: Bool
    let canSync: Bool

    var isPrimaryButtonDisabled: Bool {
        showsCommitAction ? !canCommit : !canSync
    }

    var primaryButtonTitle: String {
        showsCommitAction ? "Commit" : "Sync"
    }

    static func resolve(
        hasWorkingTreeChanges: Bool,
        hasCommitMessage: Bool,
        hasSyncWork: Bool,
        isCommitting: Bool,
        isGenerating: Bool
    ) -> MainMenuPrimaryActionState {
        let showsCommitAction = hasWorkingTreeChanges || hasCommitMessage
        let isBusy = isCommitting || isGenerating
        let canCommit = hasWorkingTreeChanges && hasCommitMessage && !isBusy
        let canSync = hasSyncWork && !hasWorkingTreeChanges && !hasCommitMessage && !isBusy

        return MainMenuPrimaryActionState(
            showsCommitAction: showsCommitAction,
            canCommit: canCommit,
            canSync: canSync
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
            hasSyncWork: gitManager.isAheadOfRemote || gitManager.isRemoteAhead,
            isCommitting: gitManager.isCommitting,
            isGenerating: aiCommitCoordinator.isGenerating
        )
    }

    var recentPaths: [String] {
        guard let decoded = try? JSONDecoder().decode([String].self, from: recentRepoPathsData) else {
            return []
        }
        return decoded
    }

    var currentRepoPath: String {
        UserDefaults.standard.string(forKey: "gitRepoPath") ?? ""
    }

    var currentProjectName: String {
        guard !currentRepoPath.isEmpty else { return "Select Project" }
        return URL(fileURLWithPath: currentRepoPath).lastPathComponent
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
}
