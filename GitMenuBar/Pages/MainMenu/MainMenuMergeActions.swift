//
//  MainMenuMergeActions.swift
//  GitMenuBar
//

import SwiftUI

extension MainMenuView {
    func performMergeToDefault() {
        let featureBranch = featureBranchName
        showMergeToDefaultConfirmation = false

        guard !featureBranch.isEmpty else { return }

        Task {
            let result = await gitManager.mergeFeatureIntoDefaultAsync(featureBranch: featureBranch)
            await MainActor.run {
                switch result {
                case .success:
                    showMergeCleanupDialog = true
                case let .failure(error):
                    featureBranchName = ""
                    defaultBranchName = ""
                    mergeError = error.localizedDescription
                }
            }
        }
    }

    func requestRemoteCleanupConfirmation(option: BranchCleanupOption) {
        pendingCleanupOption = option
        showRemoteCleanupConfirmation = true
    }

    func dismissMergeCleanup() {
        showMergeCleanupDialog = false
        featureBranchName = ""
        defaultBranchName = ""
        pendingCleanupOption = nil
    }

    func performMergeCleanup(option: BranchCleanupOption) {
        let featureBranch = featureBranchName
        showMergeCleanupDialog = false
        showRemoteCleanupConfirmation = false
        featureBranchName = ""
        defaultBranchName = ""
        pendingCleanupOption = nil

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
                    mergeError = error.localizedDescription
                }
            }
        }
    }
}
