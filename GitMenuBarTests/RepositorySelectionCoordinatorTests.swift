import Combine
@testable import GitMenuBar
import XCTest

@MainActor
final class RepositorySelectionCoordinatorTests: XCTestCase {
    func testSelectsGitRepositoryAndResetsSelectedState() throws {
        let fixture = try Fixture(isGitRepository: true)
        defer { fixture.remove() }
        fixture.gitManager.currentBranch = "stale"

        let result = fixture.coordinator.select(path: fixture.path)

        XCTAssertEqual(result, .selected(path: fixture.normalizedPath))
        XCTAssertEqual(fixture.defaults.string(forKey: AppPreferences.Keys.gitRepoPath), fixture.normalizedPath)
        XCTAssertEqual(fixture.recentStore.recentPaths(), [fixture.normalizedPath])
        XCTAssertEqual(fixture.monitor.monitoredProjects.map(\.path), [fixture.normalizedPath])
        XCTAssertEqual(fixture.gitManager.currentBranch, "")
    }

    func testSelectingGitRepositoryTwiceDoesNotDuplicateRecentOrMonitorEnrollment() throws {
        let fixture = try Fixture(isGitRepository: true)
        defer { fixture.remove() }

        _ = fixture.coordinator.select(path: fixture.path)
        _ = fixture.coordinator.select(path: fixture.path + "/.")

        XCTAssertEqual(fixture.recentStore.recentPaths(), [fixture.normalizedPath])
        XCTAssertEqual(fixture.monitor.monitoredProjects.map(\.path), [fixture.normalizedPath])
    }

    func testDefersAuthenticatedNonGitCandidateWithoutMutatingSelection() throws {
        let fixture = try Fixture(isGitRepository: false)
        defer { fixture.remove() }
        fixture.defaults.set("/previous", forKey: AppPreferences.Keys.gitRepoPath)
        fixture.recentStore.add("/previous")
        fixture.monitorStore.add("/previous")
        fixture.gitManager.currentBranch = "stale"

        let result = fixture.coordinator.select(path: fixture.path)

        XCTAssertEqual(result, .requiresRepositoryCreation(path: fixture.normalizedPath))
        XCTAssertEqual(fixture.defaults.string(forKey: AppPreferences.Keys.gitRepoPath), "/previous")
        XCTAssertEqual(fixture.recentStore.recentPaths(), ["/previous"])
        XCTAssertEqual(fixture.monitor.monitoredProjects.map(\.path), ["/previous"])
        XCTAssertEqual(fixture.gitManager.currentBranch, "stale")
    }

    func testAllowsNonGitSelectionWhenCreationIsNotActive() throws {
        let fixture = try Fixture(isGitRepository: false)
        defer { fixture.remove() }

        let result = fixture.coordinator.select(path: fixture.path, allowsNonGitSelection: true)

        XCTAssertEqual(result, .selected(path: fixture.normalizedPath))
        XCTAssertEqual(fixture.defaults.string(forKey: AppPreferences.Keys.gitRepoPath), fixture.normalizedPath)
        XCTAssertEqual(fixture.recentStore.recentPaths(), [fixture.normalizedPath])
        XCTAssertTrue(fixture.monitor.monitoredProjects.isEmpty)
    }

    func testSelectionPublishesOnlyActualPathChanges() throws {
        let fixture = try Fixture(isGitRepository: false)
        defer { fixture.remove() }
        var changes: [String] = []
        let observation = fixture.coordinator.$selectedPath
            .dropFirst()
            .sink { changes.append($0) }

        _ = fixture.coordinator.select(path: fixture.path, allowsNonGitSelection: true)
        _ = fixture.coordinator.select(path: fixture.path + "/.", allowsNonGitSelection: true)
        _ = fixture.coordinator.select(path: fixture.secondPath, allowsNonGitSelection: true)

        XCTAssertEqual(changes, [fixture.normalizedPath, fixture.normalizedSecondPath])
        XCTAssertEqual(fixture.coordinator.selectedPath, fixture.normalizedSecondPath)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let path: String
        let normalizedPath: String
        let secondPath: String
        let normalizedSecondPath: String
        let defaults: UserDefaults
        let suiteName: String
        let recentStore: RecentProjectsStore
        let monitorStore: MonitoredProjectsStore
        let monitor: ProjectMonitorStore
        let gitManager: GitManager
        let coordinator: RepositorySelectionCoordinator

        init(isGitRepository: Bool) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("GitMenuBarSelection-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            path = root.appendingPathComponent("project").path
            secondPath = root.appendingPathComponent("project-b").path
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: secondPath, withIntermediateDirectories: true)
            if isGitRepository {
                _ = try runGit(["init", "-q"], in: URL(fileURLWithPath: path))
                _ = try runGit(["init", "-q"], in: URL(fileURLWithPath: secondPath))
            }
            normalizedPath = RecentProjectsStore.normalize(path)
            normalizedSecondPath = RecentProjectsStore.normalize(secondPath)
            suiteName = "RepositorySelectionCoordinatorTests-\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            recentStore = RecentProjectsStore(defaults: defaults)
            monitorStore = MonitoredProjectsStore(defaults: defaults, key: "monitored", seededKey: "seeded")
            monitor = ProjectMonitorStore(projectStore: monitorStore)
            gitManager = GitManager(repositoryPathOverride: path)
            coordinator = RepositorySelectionCoordinator(
                gitManager: gitManager,
                projectMonitor: monitor,
                defaults: defaults,
                recentProjectsStore: recentStore
            )
        }

        func remove() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
