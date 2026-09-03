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
    @Published private(set) var selectedPath: String

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
        let storedPath = defaults.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
        selectedPath = storedPath.isEmpty ? "" : RecentProjectsStore.normalize(storedPath)
    }

    func select(path: String, allowsNonGitSelection: Bool = false) -> Result {
        let normalizedPath = RecentProjectsStore.normalize(path)
        let isGitRepository = gitManager.isGitRepository(at: normalizedPath)

        guard isGitRepository || allowsNonGitSelection else {
            return .requiresRepositoryCreation(path: normalizedPath)
        }

        let isAlreadySelected = selectedPath == normalizedPath
        if !isAlreadySelected {
            defaults.set(normalizedPath, forKey: AppPreferences.Keys.gitRepoPath)
            recentProjectsStore.add(normalizedPath)
        }
        if isGitRepository, !projectMonitor.contains(path: normalizedPath) {
            projectMonitor.add(path: normalizedPath)
        }
        guard !isAlreadySelected else { return .selected(path: normalizedPath) }

        gitManager.resetSelectedRepositoryState()
        selectedPath = normalizedPath

        return .selected(path: normalizedPath)
    }

    func clearSelection() {
        guard !selectedPath.isEmpty else { return }
        defaults.set("", forKey: AppPreferences.Keys.gitRepoPath)
        gitManager.resetSelectedRepositoryState()
        selectedPath = ""
    }
}
