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
            let result = await gitManager.mergeFeatureIntoDefaultAsync(featureBranch: featureBranch)
            await MainActor.run {
                switch result {
                case .success:
                    branchDialogs.showMergeCleanupDialog = true
                case let .failure(error):
                    branchDialogs.featureBranchName = ""
                    branchDialogs.defaultBranchName = ""
                    errorCenter.merge = error.localizedDescription
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
            let result = await gitManager.cleanupMergedBranchAsync(
                featureBranch: featureBranch,
                cleanupOption: option
            )
            switch result {
            case .success:
                break
            case let .failure(error):
                await MainActor.run {
                    errorCenter.merge = error.localizedDescription
                }
            }
        }
    }
}
