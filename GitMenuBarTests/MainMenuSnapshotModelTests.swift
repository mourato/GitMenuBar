@testable import GitMenuBar
import XCTest

@MainActor
final class MainMenuSnapshotModelTests: XCTestCase {
    func testAddingAndRemovingRecentProjectUpdatesSnapshot() throws {
        let suiteName = "MainMenuSnapshotModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RecentProjectsStore(defaults: defaults)
        let model = MainMenuSnapshotModel(recentProjectsStore: store)
        let gitManager = GitManager(repositoryPathOverride: "")
        let monitor = ProjectMonitorStore(projectStore: MonitoredProjectsStore(defaults: defaults))
        let path = "/tmp/main-menu-snapshot-project"

        func rebuild() {
            model.rebuild(
                gitManager: gitManager,
                projectMonitor: monitor,
                currentRepositoryPath: path,
                collapsedSections: (staged: false, unstaged: false),
                isLoading: false
            )
        }

        rebuild()
        XCTAssertTrue(model.renderSnapshot.recentProjects.isEmpty)

        store.upsert(path: path, name: "Snapshot Project")
        model.reloadRecentProjects()
        rebuild()

        XCTAssertEqual(model.renderSnapshot.recentProjects, [ProjectReference(path: path, name: "Snapshot Project")])
        XCTAssertEqual(model.renderSnapshot.currentProjectName, "Snapshot Project")

        store.remove(path: path)
        model.reloadRecentProjects()
        rebuild()

        XCTAssertTrue(model.recentProjectReferences.isEmpty)
        XCTAssertTrue(model.renderSnapshot.recentProjects.isEmpty)
        XCTAssertEqual(model.renderSnapshot.currentProjectName, "main-menu-snapshot-project")
    }
}
