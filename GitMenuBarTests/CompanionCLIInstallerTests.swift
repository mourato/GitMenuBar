@testable import GitMenuBar
import XCTest

final class CompanionCLIInstallerTests: XCTestCase {
    func testIsUnstableAppBundleDetectsAppTranslocation() {
        let bundle = URL(fileURLWithPath: "/private/var/folders/xx/AppTranslocation/ABC/GitMenuBar.app")
        XCTAssertTrue(CompanionCLIInstaller.isUnstableAppBundle(bundle))
    }

    func testIsUnstableAppBundleDetectsEphemeralVarFoldersPath() {
        let bundle = URL(
            fileURLWithPath: "/private/var/folders/zz/yy/T/com.apple.metadata/T/GitMenuBar.app"
        )
        XCTAssertTrue(CompanionCLIInstaller.isUnstableAppBundle(bundle))
    }

    func testIsUnstableAppBundleAcceptsApplicationsPath() {
        let bundle = URL(fileURLWithPath: "/Applications/GitMenuBar.app")
        XCTAssertFalse(CompanionCLIInstaller.isUnstableAppBundle(bundle))
    }

    func testAppBundleCandidatesPrefersNamedDistAppBeforeOtherDistApps() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dist = root.appendingPathComponent("dist", isDirectory: true)
        let preferred = dist.appendingPathComponent("GitMenuBar.app", isDirectory: true)
        let other = dist.appendingPathComponent("Other.app", isDirectory: true)
        try FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: root) }

        let candidates = CompanionCLIInstaller.appBundleCandidates(projectRoot: root)
        let distCandidatePaths = candidates
            .filter { $0.path.contains("/dist/") && $0.pathExtension == "app" }
            .map(\.standardizedFileURL.path)

        XCTAssertEqual(distCandidatePaths.first, preferred.standardizedFileURL.path)
        XCTAssertTrue(distCandidatePaths.contains(other.standardizedFileURL.path))
    }

    func testAppBundleContainingCLI() {
        let cli = URL(fileURLWithPath: "/Applications/GitMenuBar.app/Contents/Helpers/gitmenubar")
        let bundle = CompanionCLIInstaller.appBundle(containingCLI: cli)
        XCTAssertEqual(bundle.path, "/Applications/GitMenuBar.app")
    }
}
