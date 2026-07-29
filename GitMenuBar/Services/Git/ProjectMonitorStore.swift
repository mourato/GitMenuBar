import Combine
import Foundation

@MainActor
final class ProjectMonitorStore: ObservableObject {
    @Published private(set) var snapshots: [String: ProjectStatusSnapshot] = [:]

    private let projectStore: MonitoredProjectsStore
    private let runner: GitCommandRunner
    private var refreshTimer: Timer?
    private var isRefreshing = false

    init(projectStore: MonitoredProjectsStore = MonitoredProjectsStore(), runner: GitCommandRunner = GitCommandRunner()) {
        self.projectStore = projectStore
        self.runner = runner
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    var monitoredProjects: [ProjectReference] {
        projectStore.monitoredProjects()
    }

    var attentionCount: Int {
        snapshots.values.filter { [.needsAttention, .unavailable].contains($0.classification) }.count
    }

    func seed(currentPath: String, recentProjects: [ProjectReference]) {
        _ = projectStore.seedIfNeeded(currentPath: currentPath, recentProjects: recentProjects)
        refreshAll()
    }

    func add(path: String, name: String? = nil) {
        projectStore.add(path, name: name)
        refresh(path: path)
    }

    func remove(path: String) {
        projectStore.remove(path: path)
        snapshots.removeValue(forKey: RecentProjectsStore.normalize(path))
    }

    func refresh(path: String) {
        guard let project = monitoredProjects.first(where: { $0.path == RecentProjectsStore.normalize(path) }) else { return }
        refresh(projects: [project])
    }

    func refreshAll() {
        refresh(projects: monitoredProjects)
    }

    func fetchAll() {
        let projects = monitoredProjects
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            for project in projects {
                _ = self.runner.runGitCommand(in: project.path, args: ["fetch"])
                let snapshot = ProjectStatusReader(runner: self.runner).read(project: project)
                Task { @MainActor [weak self] in self?.snapshots[project.path] = snapshot }
            }
        }
    }

    private func refresh(projects: [ProjectReference]) {
        guard !isRefreshing, !projects.isEmpty else { return }
        isRefreshing = true
        let runner = self.runner
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 2
            let lock = NSLock()
            var results: [ProjectStatusSnapshot] = []
            for project in projects {
                queue.addOperation {
                    let snapshot = ProjectStatusReader(runner: runner).read(project: project)
                    lock.lock(); results.append(snapshot); lock.unlock()
                }
            }
            queue.waitUntilAllOperationsAreFinished()
            Task { @MainActor [weak self] in
                guard let self else { return }
                for snapshot in results {
                    self.snapshots[snapshot.project.path] = snapshot
                }
                self.isRefreshing = false
            }
        }
    }
}
