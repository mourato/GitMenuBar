//
//  MainMenuComputed.swift
//  GitMenuBar
//

import Foundation

extension MainMenuView {
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
        hasWorkingTreeChanges &&
            !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !gitManager.isCommitting &&
            !aiCommitCoordinator.isGenerating
    }

    var primaryButtonTitle: String {
        hasWorkingTreeChanges ? "Commit" : "Sync"
    }
}
