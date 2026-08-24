import Combine
import Foundation

@MainActor
final class ProjectCleanupStore: ObservableObject {
    @Published private(set) var rows: [ProjectCleanupRow] = []
    @Published private(set) var loadState: ProjectCleanupLoadState = .idle
    @Published private(set) var selectedPaths = Set<String>()
    @Published private(set) var isRunning = false
    @Published private(set) var cleanupProgress: GitCleanupProgress?
    @Published private(set) var result: ProjectCleanupRunResult?

    private let projectMonitor: ProjectMonitorStore
    private let runner: GitCommandRunner
    private let analyzer: @Sendable (ProjectReference, Set<String>) -> ProjectCleanupAnalysisResult
    private let onAffectedPaths: @MainActor ([String]) -> Void
    private var generation = 0
    private var cleanupRunID = UUID()

    init(
        projectMonitor: ProjectMonitorStore = ProjectMonitorStore(),
        runner: GitCommandRunner = GitCommandRunner(),
        analyzer: (@Sendable (ProjectReference, Set<String>) -> ProjectCleanupAnalysisResult)? = nil,
        onAffectedPaths: @escaping @MainActor ([String]) -> Void = { _ in }
    ) {
        self.projectMonitor = projectMonitor
        self.runner = runner
        self.analyzer = analyzer ?? Self.defaultAnalyzer(runner: runner)
        self.onAffectedPaths = onAffectedPaths
    }

    func load() {
        guard !loadState.isLoading, !isRunning else { return }
        generation += 1
        let currentGeneration = generation
        let projects = projectMonitor.monitoredProjects
        rows = []
        selectedPaths.removeAll()
        cleanupProgress = nil
        result = nil
        guard !projects.isEmpty else {
            loadState = .loaded
            return
        }
        loadState = .loading(completed: 0, total: projects.count)
        let analyzer = analyzer
        Task { [weak self] in
            let analyses = await GitExecution.runOnBackground {
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 2
                let lock = NSLock()
                var values: [String: ProjectCleanupAnalysisResult] = [:]
                for project in projects {
                    queue.addOperation {
                        let paths = Set(projects.map(\.path))
                        let value = analyzer(project, paths)
                        lock.lock(); values[project.path] = value; lock.unlock()
                        DispatchQueue.main.sync { [weak self] in
                            guard let self, generation == currentGeneration else { return }
                            if case let .loading(completed, total) = loadState {
                                loadState = .loading(completed: min(completed + 1, total), total: total)
                            }
                        }
                    }
                }
                queue.waitUntilAllOperationsAreFinished()
                return values
            }
            guard let self, generation == currentGeneration else { return }
            rows = ProjectCleanupRow.projectRows(projects: projects, analyses: analyses)
            loadState = .loaded
        }
    }

    func refresh() {
        load()
    }

    func dismissResult() {
        result = nil
    }

    func toggleSelection(path: String) {
        guard let row = rows.first(where: { $0.id == path }), row.isCanonical, !row.units.isEmpty, !isRunning else { return }
        if !selectedPaths.insert(path).inserted {
            selectedPaths.remove(path)
        }
    }

    func selectOnly(path: String) {
        guard let row = rows.first(where: { $0.id == path }), row.isCanonical, !row.units.isEmpty, !isRunning else { return }
        selectedPaths = [path]
    }

    func reviewSelected() -> ProjectCleanupReview? {
        review(for: selectedPaths)
    }

    func reviewAll() -> ProjectCleanupReview? {
        let eligible = Set(rows.filter { $0.isCanonical && !$0.units.isEmpty }.map(\.id))
        let excluded = rows.filter { !eligible.contains($0.id) }.map { row in
            ProjectCleanupProjectResult(
                project: row.project,
                items: [],
                exclusionReason: row.unavailableReason ?? (row.isShared ? "Shared repository duplicate." : "No safe cleanup candidates.")
            )
        }
        return review(for: eligible, excludedProjects: excluded)
    }

    func review(for paths: Set<String>) -> ProjectCleanupReview? {
        review(for: paths, excludedProjects: [])
    }

    private func review(for paths: Set<String>, excludedProjects: [ProjectCleanupProjectResult]) -> ProjectCleanupReview? {
        guard case .loaded = loadState, !isRunning else { return nil }
        let selected = rows.filter { paths.contains($0.id) && $0.isCanonical && !$0.units.isEmpty }
        return selected.isEmpty ? nil : ProjectCleanupReview(rows: selected, excludedProjects: excludedProjects)
    }

    func runCleanup(_ review: ProjectCleanupReview) {
        guard !isRunning else { return }
        isRunning = true
        result = nil
        let work = review.rows.compactMap { row -> CleanupWork? in
            guard let snapshot = row.snapshot else { return nil }
            return CleanupWork(project: row.project, snapshot: snapshot, units: row.units)
        }
        let total = work.reduce(0) { $0 + $1.units.count }
        let runID = UUID()
        cleanupRunID = runID
        cleanupProgress = .init(
            completed: 0,
            total: total,
            projectName: work.first?.project.name,
            detail: "Preparing cleanup"
        )
        let publishProgress: @Sendable (GitCleanupProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, isRunning, cleanupRunID == runID else { return }
                cleanupProgress = progress
            }
        }
        let runner = runner
        Task { [weak self] in
            let run = await GitExecution.runOnBackground {
                var projectResults = review.excludedProjects
                var affected = Set<String>()
                var completedOffset = 0
                for item in work {
                    let projectOffset = completedOffset
                    let projectProgress: @Sendable (GitCleanupProgress) -> Void = { progress in
                        publishProgress(.init(
                            completed: projectOffset + progress.completed,
                            total: total,
                            projectName: progress.projectName,
                            detail: progress.detail
                        ))
                    }
                    let batch = GitCleanupRepository(runner: runner).cleanup(
                        units: item.units,
                        snapshot: item.snapshot,
                        repositoryPath: item.project.path,
                        projectName: item.project.name,
                        progress: projectProgress
                    )
                    projectResults.append(ProjectCleanupProjectResult(project: item.project, items: batch.items, exclusionReason: nil))
                    if batch.items.contains(where: Self.changedStatus) {
                        affected.insert(item.project.path)
                        affected.formUnion(item.snapshot.worktrees.map(\.worktree.path))
                    }
                    completedOffset += item.units.count
                }
                return ProjectCleanupRunResult(projects: projectResults, affectedPaths: affected)
            }
            guard let self else { return }
            isRunning = false
            cleanupProgress = nil
            result = run
            projectMonitor.refreshAll()
            onAffectedPaths(Array(run.affectedPaths))
        }
    }

    private struct CleanupWork: Sendable {
        let project: ProjectReference
        let snapshot: GitWorktreeSnapshot
        let units: [GitCleanupUnit]
    }

    private nonisolated static func changedStatus(_ item: GitCleanupItemResult) -> Bool {
        if item.status == .succeeded {
            return true
        }
        if case .partiallySucceeded = item.status {
            return true
        }
        return false
    }

    private static func defaultAnalyzer(runner: GitCommandRunner) -> @Sendable (ProjectReference, Set<String>) -> ProjectCleanupAnalysisResult {
        { project, protectedPaths in
            let defaultResult = runner.runGitCommand(in: project.path, args: ["symbolic-ref", "refs/remotes/origin/HEAD"])
            let detected = defaultResult.failure ? "" : defaultResult.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").last.map(String.init) ?? ""
            let branches = runner.runGitCommand(in: project.path, args: ["branch", "--format=%(refname:short)"]).output.components(separatedBy: .newlines)
            let defaultBranch = !detected.isEmpty ? detected : branches.contains("main") ? "main" : branches.contains("master") ? "master" : "main"
            switch GitCleanupRepository(runner: runner).analyze(repositoryPath: project.path, defaultBranchName: defaultBranch, protectedWorktreePaths: protectedPaths) {
            case let .success(analysis): return .success(analysis)
            case let .failure(error): return .failure(error.localizedDescription)
            }
        }
    }

    static func preview(rows: [ProjectCleanupRow], loadState: ProjectCleanupLoadState = .loaded) -> ProjectCleanupStore {
        let store = ProjectCleanupStore()
        store.rows = rows
        store.loadState = loadState
        return store
    }
}
