//
//  MainMenuProjectActions.swift
//  GitMenuBar
//

import AppKit

extension MainMenuView {
    private var recentProjectsStore: RecentProjectsStore {
        RecentProjectsStore()
    }

    func renameProject(path: String, name: String) {
        recentProjectsStore.rename(path: path, name: name)
        projectMonitor.rename(path: path, name: name)
        recentProjectReferences = recentProjectsStore.recentProjects()
        refreshRenderSnapshot()
    }

    func revealProjectInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func removeProject(path: String) {
        recentProjectsStore.remove(path: path)
        projectMonitor.remove(path: path)
        recentProjectReferences = recentProjectsStore.recentProjects()
        if RecentProjectsStore.normalize(path) == RecentProjectsStore.normalize(currentRepositoryPath) {
            clearCurrentRepositoryPath()
            dismissTransientPresentations()
            gitManager.refresh(includeReflogHistory: false)
            refreshRenderSnapshot()
        }
    }

    private func clearCurrentRepositoryPath() {
        guard actionCoordinator.canSwitchRepository(to: currentRepositoryPath) else { return }

        repositorySelectionCoordinator.clearSelection()
    }
}
