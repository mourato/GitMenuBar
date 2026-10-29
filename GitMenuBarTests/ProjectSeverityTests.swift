import AppKit
@testable import GitMenuBar
import SwiftUI
import XCTest

final class ProjectSeverityTests: XCTestCase {
    private struct ScreenshotMode {
        let filename: String
        let appearance: NSAppearance.Name
    }

    private func makeSnapshot(
        branchName: String = "main",
        isDetachedHead: Bool = false,
        stagedCount: Int = 0,
        unstagedCount: Int = 0,
        untrackedCount: Int = 0,
        aheadCount: Int = 0,
        behindCount: Int = 0,
        hasUpstream: Bool = true,
        unmergedBranchCount: Int = 0
    ) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/test-project", name: "TestProject"),
            branchName: branchName,
            isDetachedHead: isDetachedHead,
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            lineDiff: .zero,
            aheadCount: aheadCount,
            behindCount: behindCount,
            hasUpstream: hasUpstream,
            lastRefreshedAt: Date(),
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: 0,
            unmergedBranchCount: unmergedBranchCount,
            stashCount: 0,
            lastActivityAt: Date(),
            pullRequests: []
        )
    }

    func testDivergedOrBehindSeverity() {
        // Behind only
        let behindSnapshot = makeSnapshot(behindCount: 2)
        XCTAssertEqual(behindSnapshot.severity, .divergedOrBehind)

        // Diverged (ahead and behind)
        let divergedSnapshot = makeSnapshot(aheadCount: 3, behindCount: 1)
        XCTAssertEqual(divergedSnapshot.severity, .divergedOrBehind)
    }

    func testUncommittedChangesSeverity() {
        // Staged changes only
        let stagedSnapshot = makeSnapshot(stagedCount: 1)
        XCTAssertEqual(stagedSnapshot.severity, .uncommittedChanges)

        // Unstaged changes only
        let unstagedSnapshot = makeSnapshot(unstagedCount: 2)
        XCTAssertEqual(unstagedSnapshot.severity, .uncommittedChanges)

        // Both staged and unstaged changes
        let bothSnapshot = makeSnapshot(stagedCount: 1, unstagedCount: 1)
        XCTAssertEqual(bothSnapshot.severity, .uncommittedChanges)
    }

    func testUntrackedFilesAloneAreNotAWarning() {
        // Untracked files alone must not produce uncommittedChanges severity or a warning dot
        let untrackedSnapshot = makeSnapshot(untrackedCount: 4)
        XCTAssertNil(untrackedSnapshot.severity)
    }

    func testUnmergedBranchesOnlySeverity() {
        let unmergedSnapshot = makeSnapshot(unmergedBranchCount: 2)
        XCTAssertEqual(unmergedSnapshot.severity, .unmergedOnly)
    }

    func testSeverityPrecedence() {
        // Diverged/behind takes precedence over uncommitted changes
        let behindAndDirtySnapshot = makeSnapshot(stagedCount: 2, behindCount: 1)
        XCTAssertEqual(behindAndDirtySnapshot.severity, .divergedOrBehind)

        // Uncommitted changes take precedence over unmerged branches
        let dirtyAndUnmergedSnapshot = makeSnapshot(stagedCount: 1, unmergedBranchCount: 3)
        XCTAssertEqual(dirtyAndUnmergedSnapshot.severity, .uncommittedChanges)

        // Diverged/behind takes precedence over unmerged branches
        let behindAndUnmergedSnapshot = makeSnapshot(behindCount: 1, unmergedBranchCount: 3)
        XCTAssertEqual(behindAndUnmergedSnapshot.severity, .divergedOrBehind)
    }

    func testCleanSnapshotHasNoSeverity() {
        let cleanSnapshot = makeSnapshot()
        XCTAssertNil(cleanSnapshot.severity)
    }

    func testIsDefaultBranch() {
        XCTAssertTrue(makeSnapshot(branchName: "main").isDefaultBranch)
        XCTAssertTrue(makeSnapshot(branchName: "master").isDefaultBranch)
        XCTAssertFalse(makeSnapshot(branchName: "feature/login").isDefaultBranch)
        XCTAssertFalse(makeSnapshot(branchName: "develop").isDefaultBranch)
        XCTAssertFalse(makeSnapshot(branchName: "main", isDetachedHead: true).isDefaultBranch)
        XCTAssertFalse(makeSnapshot(branchName: "").isDefaultBranch)
    }

    @MainActor
    func testRenderSidebarScreenshots() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ScreenshotTests.\(UUID().uuidString)"))
        let projectStore = MonitoredProjectsStore(defaults: defaults, key: "p", seededKey: "s")
        let monitor = ProjectMonitorStore(projectStore: projectStore)

        let p1 = "/tmp/repo-diverged"
        let p2 = "/tmp/repo-uncommitted"
        let p3 = "/tmp/repo-unmerged"
        let p4 = "/tmp/repo-clean"
        let p5 = "/tmp/repo-feature"

        projectStore.add(p1)
        projectStore.add(p2)
        projectStore.add(p3)
        projectStore.add(p4)
        projectStore.add(p5)

        let s1 = ProjectStatusSnapshot(
            project: ProjectReference(path: p1, name: "Backend API"),
            branchName: "main",
            isDetachedHead: false,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: 1,
            behindCount: 2,
            hasUpstream: true,
            lastRefreshedAt: Date(),
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: 0,
            unmergedBranchCount: 0,
            stashCount: 0,
            lastActivityAt: Date(),
            pullRequests: []
        )
        let s2 = ProjectStatusSnapshot(
            project: ProjectReference(path: p2, name: "Web Client"),
            branchName: "main",
            isDetachedHead: false,
            stagedCount: 2,
            unstagedCount: 3,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: 0,
            behindCount: 0,
            hasUpstream: true,
            lastRefreshedAt: Date(),
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: 0,
            unmergedBranchCount: 0,
            stashCount: 0,
            lastActivityAt: Date(),
            pullRequests: []
        )
        let s3 = ProjectStatusSnapshot(
            project: ProjectReference(path: p3, name: "Docs Site"),
            branchName: "main",
            isDetachedHead: false,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: 0,
            behindCount: 0,
            hasUpstream: true,
            lastRefreshedAt: Date(),
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: 0,
            unmergedBranchCount: 1,
            stashCount: 0,
            lastActivityAt: Date(),
            pullRequests: []
        )
        let s4 = ProjectStatusSnapshot(
            project: ProjectReference(path: p4, name: "Mobile App"),
            branchName: "main",
            isDetachedHead: false,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: 0,
            behindCount: 0,
            hasUpstream: true,
            lastRefreshedAt: Date(),
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: 0,
            unmergedBranchCount: 0,
            stashCount: 0,
            lastActivityAt: Date(),
            pullRequests: []
        )
        let s5 = ProjectStatusSnapshot(
            project: ProjectReference(path: p5, name: "Infra Config"),
            branchName: "feature/deploy",
            isDetachedHead: false,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: 1,
            behindCount: 0,
            hasUpstream: true,
            lastRefreshedAt: Date(),
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: 0,
            unmergedBranchCount: 0,
            stashCount: 0,
            lastActivityAt: Date(),
            pullRequests: []
        )

        monitor.refreshOperation = { project, _ in
            switch project.path {
            case p1: s1
            case p2: s2
            case p3: s3
            case p4: s4
            default: s5
            }
        }
        monitor.refresh(path: p1)
        monitor.refresh(path: p2)
        monitor.refresh(path: p3)
        monitor.refresh(path: p4)
        monitor.refresh(path: p5)

        let targetDir = "/Users/usuario/.t3/userdata/providers/antigravity/ac0a3dfd6dddb20962cecff6ee5fe65e19d3923be20e52c5ab52ff877f7e4c32/antigravity-acp/brain/b38deb72-9309-4c3e-942e-be927418e7b7"

        let modes = [
            ScreenshotMode(filename: "sidebar-dark.png", appearance: .darkAqua),
            ScreenshotMode(filename: "sidebar-light.png", appearance: .aqua),
            ScreenshotMode(filename: "sidebar-increase-contrast.png", appearance: .accessibilityHighContrastDarkAqua)
        ]

        let viewSize = CGSize(width: 280, height: 460)

        for mode in modes {
            let view = ProjectsSidebarView(
                currentPath: p1,
                onSelect: { _ in },
                onReveal: { _ in },
                onStopMonitoring: { _ in },
                onRemove: { _ in },
                onRename: { _, _ in },
                onProjectCleanup: {},
                onAddProject: {},
                onRefreshAll: {},
                onFetchAll: {},
                onOpenSettings: {}
            )
            .environment(monitor)
            .environment(UsageQuotaStore())
            .frame(width: viewSize.width, height: viewSize.height)

            let hostingView = NSHostingView(rootView: view)
            hostingView.appearance = NSAppearance(named: mode.appearance)
            hostingView.frame = NSRect(origin: .zero, size: viewSize)
            hostingView.layoutSubtreeIfNeeded()

            guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
                continue
            }
            hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                continue
            }
            let fileURL = URL(fileURLWithPath: "\(targetDir)/\(mode.filename)")
            try pngData.write(to: fileURL)
        }
    }
}
