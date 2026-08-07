@testable import GitMenuBar
import XCTest

@MainActor
final class ProjectCleanupStoreTests: XCTestCase {
    func testRowsKeepEveryProjectAndAssignSharedIdentityToOneRow() {
        let first = ProjectReference(path: "/tmp/project-a", name: "A")
        let second = ProjectReference(path: "/tmp/project-b", name: "B")
        let snapshot = GitWorktreeSnapshot(
            repositoryPath: first.path,
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "local",
            worktrees: [],
            branches: [],
            repositoryIdentity: "/shared"
        )
        let analysis = GitCleanupAnalysis(
            repositoryPath: first.path,
            repositoryIdentity: "/shared",
            defaultBranchRef: "refs/heads/main",
            snapshot: snapshot
        )

        let rows = ProjectCleanupRow.projectRows(
            projects: [first, second],
            analyses: [
                first.path: .success(analysis),
                second.path: .success(analysis)
            ]
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.filter(\.isCanonical).count, 1)
        XCTAssertEqual(rows.filter(\.isShared).count, 1)
    }

    func testRowsKeepUnavailableProjectsVisible() {
        let project = ProjectReference(path: "/tmp/unavailable")

        let rows = ProjectCleanupRow.projectRows(
            projects: [project],
            analyses: [project.path: .failure("Repository is unavailable.")]
        )

        XCTAssertEqual(rows.first?.unavailableReason, "Repository is unavailable.")
        XCTAssertFalse(rows.first?.isCanonical == true)
    }

    func testSelectOnlyReplacesSelectionAndReview() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ProjectCleanupStoreTests-\(UUID().uuidString)"))
        let persisted = MonitoredProjectsStore(defaults: defaults)
        persisted.add("/tmp/project-a", name: "A")
        persisted.add("/tmp/project-b", name: "B")
        let monitor = ProjectMonitorStore(projectStore: persisted)
        let store = ProjectCleanupStore(projectMonitor: monitor) { project, _ in
            .success(Self.analysis(for: project))
        }

        store.load()
        for _ in 0 ..< 100 where store.loadState != .loaded {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let paths = Set(monitor.monitoredProjects.map(\.path))
        XCTAssertEqual(paths.count, 2)
        let first = try XCTUnwrap(paths.first)
        let second = try XCTUnwrap(paths.dropFirst().first)

        store.toggleSelection(path: first)
        store.selectOnly(path: second)

        XCTAssertEqual(store.selectedPaths, [second])
        XCTAssertEqual(store.reviewSelected()?.rows.map(\.id), [second])
    }

    func testRunResultAggregatesPartialSkippedFailedAndExcluded() {
        let project = ProjectReference(path: "/tmp/project", name: "Project")
        let unit = Self.unit(repositoryIdentity: project.path)
        let items = [
            GitCleanupItemResult(unit: unit, status: .succeeded),
            GitCleanupItemResult(unit: unit, status: .partiallySucceeded(reason: "branch kept")),
            GitCleanupItemResult(unit: unit, status: .skipped(reason: "stale")),
            GitCleanupItemResult(unit: unit, status: .failed(reason: "locked"))
        ]
        let excluded = ProjectCleanupProjectResult(project: ProjectReference(path: "/tmp/unavailable"), items: [], exclusionReason: "Unavailable")

        let result = ProjectCleanupRunResult(
            projects: [
                ProjectCleanupProjectResult(project: project, items: items, exclusionReason: nil),
                excluded
            ],
            affectedPaths: []
        )

        XCTAssertEqual(result.completedCount, 1)
        XCTAssertEqual(result.partialCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.excludedCount, 1)
    }

    private nonisolated static func analysis(for project: ProjectReference) -> GitCleanupAnalysis {
        let unit = unit(repositoryIdentity: project.path)
        let snapshot = GitWorktreeSnapshot(
            repositoryPath: project.path,
            defaultBranchName: "main",
            defaultBranchRef: "refs/heads/main",
            analysisDescription: "local",
            worktrees: [],
            branches: [],
            repositoryIdentity: project.path,
            cleanupUnits: [unit]
        )
        return GitCleanupAnalysis(repositoryPath: project.path, repositoryIdentity: project.path, defaultBranchRef: "refs/heads/main", snapshot: snapshot)
    }

    private nonisolated static func unit(repositoryIdentity: String) -> GitCleanupUnit {
        GitCleanupUnit(
            repositoryIdentity: repositoryIdentity,
            branch: GitBranchCleanupInfo(
                reference: GitBranchReference(name: "feature/cleanup", headHash: "hash", isRemote: false),
                status: .mergedIntoDefault,
                worktreePath: nil
            ),
            worktree: nil
        )
    }
}
