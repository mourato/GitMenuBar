@testable import GitMenuBar
import XCTest

final class MonitoredProjectFileWatcherTests: XCTestCase {
    func testRoutesProjectFilesButNotSiblingDirectories() {
        let projects = [ProjectReference(path: "/tmp/repo")]

        let affected = MonitoredProjectFileRouter.affectedProjects(
            for: ["/tmp/repo/Sources/App.swift", "/tmp/repo-other/file.swift"],
            projects: projects
        )

        XCTAssertEqual(affected.map(\.path), ["/tmp/repo"])
    }

    func testRoutesProjectRootAndNestedProjects() {
        let projects = [
            ProjectReference(path: "/tmp/repo"),
            ProjectReference(path: "/tmp/repo/packages/app")
        ]

        let affected = MonitoredProjectFileRouter.affectedProjects(
            for: ["/tmp/repo/packages/app"],
            projects: projects
        )

        XCTAssertEqual(affected.map(\.path), ["/tmp/repo", "/tmp/repo/packages/app"])
    }

    func testRoutesMultipleProjectsAndIgnoresOutsidePaths() {
        let projects = [
            ProjectReference(path: "/tmp/first"),
            ProjectReference(path: "/tmp/second")
        ]

        let affected = MonitoredProjectFileRouter.affectedProjects(
            for: ["/tmp/first/file", "/tmp/second/file", "/tmp/other/file"],
            projects: projects
        )

        XCTAssertEqual(affected.map(\.path), ["/tmp/first", "/tmp/second"])
    }

    func testNormalizesChangedPathsBeforeRouting() {
        let projects = [ProjectReference(path: "/tmp/repo")]

        let affected = MonitoredProjectFileRouter.affectedProjects(
            for: ["/tmp/repo/Sources/../README.md"],
            projects: projects
        )

        XCTAssertEqual(affected.map(\.path), ["/tmp/repo"])
    }
}
