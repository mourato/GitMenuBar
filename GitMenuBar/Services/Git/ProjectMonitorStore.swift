import Combine
import Foundation

@MainActor
final class ProjectMonitorStore: ObservableObject {
    @Published private(set) var snapshots: [String: ProjectStatusSnapshot] = [:]

    private let projectStore: MonitoredProjectsStore
    private let runner: GitCommandRunner
    private nonisolated(unsafe) var refreshTimer: Timer?
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
        let reader = ProjectStatusReader(runner: runner)
        var seededSnapshots: [String: ProjectStatusSnapshot] = [:]
        func read(_ project: ProjectReference) -> ProjectStatusSnapshot {
            if let snapshot = seededSnapshots[project.path] {
                return snapshot
            }
            let snapshot = reader.read(project: project)
            seededSnapshots[project.path] = snapshot
            return snapshot
        }
        let current = currentPath.isEmpty ? nil : ProjectReference(path: currentPath)
        let validCurrentPath = current.flatMap { read($0).lastErrorDescription == nil ? $0.path : nil } ?? ""
        let validRecentProjects = recentProjects.filter { read($0).lastErrorDescription == nil }
        _ = projectStore.seedIfNeeded(
            currentPath: validCurrentPath,
            recentProjects: validRecentProjects
        )
        for snapshot in seededSnapshots.values where snapshot.lastErrorDescription == nil {
            snapshots[snapshot.project.path] = snapshot
        }
        if projectStore.monitoredProjects().contains(where: { snapshots[$0.path] == nil }) {
            refreshAll()
        }
    }

    func add(path: String, name: String? = nil) {
        projectStore.add(path, name: name)
        refresh(path: path)
    }

    func contains(path: String) -> Bool {
        projectStore.contains(path: path)
    }

    func remove(path: String) {
        projectStore.remove(path: path)
        snapshots.removeValue(forKey: RecentProjectsStore.normalize(path))
    }

    func rename(path: String, name: String) {
        projectStore.rename(path: path, name: name)
        let normalizedPath = RecentProjectsStore.normalize(path)
        guard let snapshot = snapshots[normalizedPath] else { return }
        snapshots[normalizedPath] = ProjectStatusSnapshot(
            project: ProjectReference(path: snapshot.project.path, name: name),
            branchName: snapshot.branchName,
            isDetachedHead: snapshot.isDetachedHead,
            stagedCount: snapshot.stagedCount,
            unstagedCount: snapshot.unstagedCount,
            untrackedCount: snapshot.untrackedCount,
            lineDiff: snapshot.lineDiff,
            aheadCount: snapshot.aheadCount,
            behindCount: snapshot.behindCount,
            hasUpstream: snapshot.hasUpstream,
            lastRefreshedAt: snapshot.lastRefreshedAt,
            lastErrorDescription: snapshot.lastErrorDescription
        )
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
                _ = runner.runGitCommand(in: project.path, args: ["fetch"])
                let snapshot = ProjectStatusReader(runner: runner).read(project: project)
                Task { @MainActor [weak self] in self?.snapshots[project.path] = snapshot }
            }
        }
    }

    private func refresh(projects: [ProjectReference]) {
        guard !isRefreshing, !projects.isEmpty else { return }
        isRefreshing = true
        let runner = runner
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
                    snapshots[snapshot.project.path] = snapshot
                }
                isRefreshing = false
            }
        }
    }
}
