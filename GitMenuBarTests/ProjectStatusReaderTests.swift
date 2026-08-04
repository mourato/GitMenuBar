@testable import GitMenuBar
import XCTest

final class ProjectStatusReaderTests: XCTestCase {
    func testParsesCleanBranchAndUpstream() {
        let fixture = "# branch.oid abc\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +0 -0\0"
        let result = ProjectStatusPorcelainParser.parse(fixture)

        XCTAssertEqual(result, .init(branchName: "main", hasUpstream: true))
    }

    func testParsesStatusCountsWithoutUsingNewlines() {
        let output = "# branch.head main\u{0}# branch.ab +3 -2\u{0}"
            + "1 M. 100644 a a a path with\nnewline\u{0}"
            + "1 .M 100644 a a a modified\u{0}? untracked\u{0}? another\u{0}"

        let result = ProjectStatusPorcelainParser.parse(output)

        XCTAssertEqual(
            result,
            .init(branchName: "main", stagedCount: 1, unstagedCount: 1, untrackedCount: 2, aheadCount: 3, behindCount: 2)
        )
    }

    func testParsesDetachedAndMalformedHeadersWithDefaults() {
        let fixture = "# branch.oid 0123456789abcdef\0# branch.head (detached)\0"
            + "# branch.ab malformed\0u malformed\0"
        let result = ProjectStatusPorcelainParser.parse(fixture)

        XCTAssertEqual(result.branchName, "0123456")
        XCTAssertTrue(result.isDetachedHead)
        XCTAssertFalse(result.hasUpstream)
        XCTAssertEqual(result.aheadCount, 0)
        XCTAssertEqual(result.behindCount, 0)
    }

    func testReaderPreservesUnavailableAndNonGitErrors() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitMenuBarStatusReader-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = ProjectStatusReader(runner: GitCommandRunner())
        let missing = reader.read(project: ProjectReference(path: root.appendingPathComponent("missing").path))
        let nonGit = reader.read(project: ProjectReference(path: root.path))

        XCTAssertEqual(missing.lastErrorDescription, "Folder unavailable")
        XCTAssertEqual(nonGit.lastErrorDescription, "Not a Git repository")
    }
}
