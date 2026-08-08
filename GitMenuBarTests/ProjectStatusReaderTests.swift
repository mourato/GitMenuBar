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
            .init(
                branchName: "main",
                stagedCount: 1,
                unstagedCount: 1,
                untrackedCount: 2,
                untrackedPaths: ["untracked", "another"],
                aheadCount: 3,
                behindCount: 2
            )
        )
    }

    func testParsesMixedChangesAndIgnoresMalformedBranchHeaders() {
        let output = "# branch.head main\0# branch.upstream \0# branch.ab +x -2\0"
            + "1 MM 100644 a a a mixed\0"
        let result = ProjectStatusPorcelainParser.parse(output)

        XCTAssertEqual(result.stagedCount, 1)
        XCTAssertEqual(result.unstagedCount, 1)
        XCTAssertEqual(result.aheadCount, 0)
        XCTAssertEqual(result.behindCount, 0)
        XCTAssertFalse(result.hasUpstream)
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

    func testReaderPreservesGitStatusFailureDescription() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMenuBarStatusFailure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try runGit(["init", "-q"], in: root)
        try Data("broken".utf8).write(to: root.appendingPathComponent(".git/index"))

        let snapshot = ProjectStatusReader(runner: GitCommandRunner())
            .read(project: ProjectReference(path: root.path))

        XCTAssertNotNil(snapshot.lastErrorDescription)
        XCTAssertNotEqual(snapshot.lastErrorDescription, "Not a Git repository")
    }

    func testReaderAggregatesStagedUnstagedAndUntrackedLineDiffs() throws {
        let root = try createTemporaryGitRepository(testName: #function)
        defer { try? FileManager.default.removeItem(at: root) }

        let trackedFile = root.appendingPathComponent("README.md")
        try "base\nstaged\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: root)
        try "changed\nstaged\nunstaged\n".write(to: trackedFile, atomically: true, encoding: .utf8)

        let untrackedFile = root.appendingPathComponent("New.swift")
        try "new\nfile\n".write(to: untrackedFile, atomically: true, encoding: .utf8)

        let snapshot = ProjectStatusReader(runner: GitCommandRunner())
            .read(project: ProjectReference(path: root.path), includeLineDiff: true)

        XCTAssertEqual(snapshot.lineDiff, LineDiffStats(added: 5, removed: 1))
    }

    func testCompactReaderPreservesStatusWithoutReadingLineDiffs() throws {
        let root = try createTemporaryGitRepository(testName: #function)
        defer { try? FileManager.default.removeItem(at: root) }

        try "tracked\n".write(
            to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8
        )
        try runGit(["add", "README.md"], in: root)
        try runGit(["commit", "-qm", "initial"], in: root)
        try "changed\n".write(
            to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8
        )
        try String(repeating: "untracked\n", count: 10000).write(
            to: root.appendingPathComponent("large-untracked.txt"), atomically: true, encoding: .utf8
        )

        let snapshot = ProjectStatusReader(runner: GitCommandRunner()).read(
            project: ProjectReference(path: root.path), includeLineDiff: false
        )

        XCTAssertEqual(snapshot.branchName, try runGit(["branch", "--show-current"], in: root).trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(snapshot.unstagedCount, 1)
        XCTAssertEqual(snapshot.untrackedCount, 1)
        XCTAssertEqual(snapshot.lineDiff, .zero)
        XCTAssertNil(snapshot.lastErrorDescription)
    }

    func testReaderCountsStagedLinesBeforeFirstCommit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMenuBarStatusReaderNoHead-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try runGit(["init", "-q"], in: root)

        try "new\nfile\n".write(
            to: root.appendingPathComponent("New.swift"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "New.swift"], in: root)

        let snapshot = ProjectStatusReader(runner: GitCommandRunner())
            .read(project: ProjectReference(path: root.path), includeLineDiff: true)

        XCTAssertEqual(snapshot.lineDiff, LineDiffStats(added: 2, removed: 0))
    }
}
