import Combine
import Foundation

@MainActor
final class ProjectMonitorStore: ObservableObject {
    /// Immutable value data is filled once on the worker and only crosses back to the actor.
    private struct SeedResult: @unchecked Sendable {
        let candidates: [ProjectReference]
        let snapshots: [String: ProjectStatusSnapshot]
    }

    @Published private(set) var snapshots: [String: ProjectStatusSnapshot] = [:]

    private let projectStore: MonitoredProjectsStore
    private let runner: GitCommandRunner
    private nonisolated(unsafe) var refreshTimer: Timer?
    private var isRefreshing = false
    private var refreshGeneration = 0
    private var fetchGeneration = 0
    private var pendingRefreshPaths = Set<String>()

    #if DEBUG
        var fetchOperation: ((ProjectReference, GitCommandRunner) -> ProjectStatusSnapshot)?
        var refreshOperation: ((ProjectReference, GitCommandRunner) -> ProjectStatusSnapshot)?
    #endif

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

    func seed(currentPath: String, recentProjects: [ProjectReference]) async {
        fetchGeneration += 1
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        let currentProject = currentPath.isEmpty ? nil : ProjectReference(path: currentPath)
        var candidates = currentPath.isEmpty ? [] : [ProjectReference(path: currentPath)]
        candidates.append(contentsOf: recentProjects)
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.path).inserted }
        let runner = runner
        let seedInput = SeedResult(candidates: candidates, snapshots: [:])

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<SeedResult, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let reader = ProjectStatusReader(runner: runner)
                var readSnapshots: [String: ProjectStatusSnapshot] = [:]
                for project in seedInput.candidates {
                    readSnapshots[project.path] = reader.read(project: project, includeLineDiff: false)
                }

                continuation.resume(returning: SeedResult(candidates: seedInput.candidates, snapshots: readSnapshots))
            }
        }
        guard generation == refreshGeneration else { return }
        let validProjects = result.candidates.filter {
            result.snapshots[$0.path]?.lastErrorDescription == nil
        }
        let validCurrentPath = currentProject.flatMap { current in
            validProjects.contains(where: { $0.path == current.path }) ? current.path : nil
        } ?? ""
        let validRecentProjects = validProjects.filter { $0.path != validCurrentPath }
        _ = projectStore.seedIfNeeded(
            currentPath: validCurrentPath,
            recentProjects: validRecentProjects
        )
        for snapshot in result.snapshots.values where snapshot.lastErrorDescription == nil {
            snapshots[snapshot.project.path] = snapshot
        }
        isRefreshing = false
        refreshPendingPathsIfNeeded()
        if !isRefreshing, projectStore.monitoredProjects().contains(where: { snapshots[$0.path] == nil }) {
            refreshAll()
        }
    }

    func add(path: String, name: String? = nil) {
        fetchGeneration += 1
        projectStore.add(path, name: name)
        refresh(path: path)
    }

    func contains(path: String) -> Bool {
        projectStore.contains(path: path)
    }

    func remove(path: String) {
        fetchGeneration += 1
        projectStore.remove(path: path)
        snapshots.removeValue(forKey: RecentProjectsStore.normalize(path))
    }

    func rename(path: String, name: String) {
        fetchGeneration += 1
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
            lastErrorDescription: snapshot.lastErrorDescription,
            branchesWithoutUpstreamCount: snapshot.branchesWithoutUpstreamCount,
            unpushedBranchCount: snapshot.unpushedBranchCount,
            unmergedBranchCount: snapshot.unmergedBranchCount,
            stashCount: snapshot.stashCount,
            lastActivityAt: snapshot.lastActivityAt
        )
    }

    func refresh(path: String) {
        let normalizedPath = RecentProjectsStore.normalize(path)
        guard let project = monitoredProjects.first(where: { $0.path == normalizedPath }) else { return }
        if isRefreshing {
            pendingRefreshPaths.insert(normalizedPath)
            return
        }
        refresh(projects: [project])
    }

    func refreshAll() {
        refresh(projects: monitoredProjects)
    }

    func fetchAll() {
        guard !isRefreshing else { return }
        let projects = monitoredProjects
        fetchGeneration += 1
        let generation = fetchGeneration
        let runner = runner
        #if DEBUG
            let fetchOperation = fetchOperation
        #endif
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for project in projects {
                let snapshot: ProjectStatusSnapshot
                #if DEBUG
                    if let fetchOperation {
                        snapshot = fetchOperation(project, runner)
                    } else {
                        _ = runner.runGitCommand(in: project.path, args: ["fetch"])
                        snapshot = ProjectStatusReader(runner: runner).read(project: project, includeLineDiff: false)
                    }
                #else
                    _ = runner.runGitCommand(in: project.path, args: ["fetch"])
                    snapshot = ProjectStatusReader(runner: runner).read(project: project, includeLineDiff: false)
                #endif
                Task { @MainActor [weak self] in
                    self?.publishFetched(snapshot, generation: generation)
                }
            }
        }
    }

    private func refresh(projects: [ProjectReference]) {
        guard !isRefreshing, !projects.isEmpty else { return }
        refreshGeneration += 1
        fetchGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        let runner = runner
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 2
            let lock = NSLock()
            var results: [ProjectStatusSnapshot] = []
            for project in projects {
                queue.addOperation {
                    #if DEBUG
                        let snapshot = self?.refreshOperation?(project, runner)
                            ?? ProjectStatusReader(runner: runner).read(project: project, includeLineDiff: false)
                    #else
                        let snapshot = ProjectStatusReader(runner: runner).read(project: project, includeLineDiff: false)
                    #endif
                    lock.lock(); results.append(snapshot); lock.unlock()
                }
            }
            queue.waitUntilAllOperationsAreFinished()
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == refreshGeneration else { return }
                for snapshot in results {
                    guard projectStore.contains(path: snapshot.project.path) else { continue }
                    snapshots[snapshot.project.path] = snapshot
                }
                isRefreshing = false
                refreshPendingPathsIfNeeded()
            }
        }
    }

    private func publishFetched(_ snapshot: ProjectStatusSnapshot, generation: Int) {
        guard generation == fetchGeneration,
              projectStore.contains(path: snapshot.project.path)
        else { return }
        snapshots[snapshot.project.path] = snapshot
    }

    private func refreshPendingPathsIfNeeded() {
        guard !pendingRefreshPaths.isEmpty else { return }
        let paths = pendingRefreshPaths
        pendingRefreshPaths.removeAll()
        let projects = monitoredProjects.filter { paths.contains($0.path) }
        refresh(projects: projects)
    }
}
