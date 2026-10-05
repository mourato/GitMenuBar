//
//  MainMenuMergeActions.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    func performMergeToDefault() {
        let featureBranch = branchDialogs.featureBranchName
        branchDialogs.showMergeToDefaultConfirmation = false

        guard !featureBranch.isEmpty else { return }

        Task {
            let result = await actionCoordinator.mergeFeatureIntoDefault(featureBranch: featureBranch)
            await MainActor.run {
                switch result {
                case .succeeded:
                    branchDialogs.showMergeCleanupDialog = true
                case let .failed(message):
                    branchDialogs.featureBranchName = ""
                    branchDialogs.defaultBranchName = ""
                    errorCenter.merge = message
                }
            }
        }
    }

    func requestRemoteCleanupConfirmation(option: BranchCleanupOption) {
        branchDialogs.pendingCleanupOption = option
        branchDialogs.showRemoteCleanupConfirmation = true
    }

    func dismissMergeCleanup() {
        branchDialogs.showMergeCleanupDialog = false
        branchDialogs.featureBranchName = ""
        branchDialogs.defaultBranchName = ""
        branchDialogs.pendingCleanupOption = nil
    }

    func performMergeCleanup(option: BranchCleanupOption) {
        let featureBranch = branchDialogs.featureBranchName
        branchDialogs.showMergeCleanupDialog = false
        branchDialogs.showRemoteCleanupConfirmation = false
        branchDialogs.featureBranchName = ""
        branchDialogs.defaultBranchName = ""
        branchDialogs.pendingCleanupOption = nil

        guard !featureBranch.isEmpty else { return }

        Task {
            let result = await actionCoordinator.cleanupMergedBranch(
                featureBranch: featureBranch,
                cleanupOption: option
            )
            switch result {
            case .succeeded:
                break
            case let .failed(message):
                await MainActor.run {
                    errorCenter.merge = message
                }
            }
        }
    }
}
