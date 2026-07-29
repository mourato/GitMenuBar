//
//  MainMenuProjectActions.swift
//  GitMenuBar
//

import AppKit

extension MainMenuView {
    private var recentProjectsStore: RecentProjectsStore {
        RecentProjectsStore()
    }

    func addToRecents(_ path: String) {
        recentProjectsStore.add(path)
        recentProjectReferences = recentProjectsStore.recentProjects()
    }

    func renameProject(path: String, name: String) {
        recentProjectsStore.rename(path: path, name: name)
        recentProjectReferences = recentProjectsStore.recentProjects()
        refreshRenderSnapshot()
    }

    func revealProjectInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func removeProject(path: String) {
        recentProjectsStore.remove(path: path)
        recentProjectReferences = recentProjectsStore.recentProjects()
        if RecentProjectsStore.normalize(path) == RecentProjectsStore.normalize(currentRepositoryPath) {
            setCurrentRepositoryPath("")
            showRepositoryOptionsPopover = false
            gitManager.refresh(includeReflogHistory: false)
            refreshRenderSnapshot()
        }
    }

    func setCurrentRepositoryPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
        currentRepositoryPath = path
    }
}
