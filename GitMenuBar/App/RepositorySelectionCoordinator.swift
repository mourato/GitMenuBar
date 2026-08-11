import Foundation

@MainActor
final class RepositorySelectionCoordinator: ObservableObject {
    enum Result: Equatable {
        case selected(path: String)
        case requiresRepositoryCreation(path: String)
    }

    private let gitManager: GitManager
    private let projectMonitor: ProjectMonitorStore
    private let defaults: UserDefaults
    private let recentProjectsStore: RecentProjectsStore

    init(
        gitManager: GitManager,
        projectMonitor: ProjectMonitorStore,
        defaults: UserDefaults = .standard,
        recentProjectsStore: RecentProjectsStore? = nil
    ) {
        self.gitManager = gitManager
        self.projectMonitor = projectMonitor
        self.defaults = defaults
        self.recentProjectsStore = recentProjectsStore ?? RecentProjectsStore(defaults: defaults)
    }

    func select(path: String, allowsNonGitSelection: Bool = false) -> Result {
        let normalizedPath = RecentProjectsStore.normalize(path)
        let isGitRepository = gitManager.isGitRepository(at: normalizedPath)

        guard isGitRepository || allowsNonGitSelection else {
            return .requiresRepositoryCreation(path: normalizedPath)
        }

        defaults.set(normalizedPath, forKey: AppPreferences.Keys.gitRepoPath)
        recentProjectsStore.add(normalizedPath)
        if isGitRepository, !projectMonitor.contains(path: normalizedPath) {
            projectMonitor.add(path: normalizedPath)
        }
        gitManager.resetSelectedRepositoryState()

        return .selected(path: normalizedPath)
    }
}
