@testable import GitMenuBar
import XCTest

final class WorktreeParserTests: XCTestCase {
    private let parser = WorktreeParser()

    func testParseMainAndLinkedWorktrees() throws {
        let output = [
            "worktree /Users/test/Project",
            "HEAD 1111111111111111111111111111111111111111",
            "branch refs/heads/main",
            "",
            "worktree /Users/test/Project feature",
            "HEAD 2222222222222222222222222222222222222222",
            "branch refs/heads/feature/ui"
        ].joined(separator: "\n")

        let worktrees = try parser.parse(output)

        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(worktrees[0].path, "/Users/test/Project")
        XCTAssertEqual(worktrees[0].branchName, "main")
        XCTAssertTrue(worktrees[0].isMainWorktree)
        XCTAssertEqual(worktrees[1].path, "/Users/test/Project feature")
        XCTAssertEqual(worktrees[1].branchName, "feature/ui")
        XCTAssertFalse(worktrees[1].isMainWorktree)
    }

    func testParseDetachedWorktree() throws {
        let output = [
            "worktree /Users/test/Detached",
            "HEAD abcdefabcdefabcdefabcdefabcdefabcdefabcd"
        ].joined(separator: "\n")

        let worktree = try XCTUnwrap(parser.parse(output).first)

        XCTAssertNil(worktree.branchName)
        XCTAssertTrue(worktree.isDetached)
    }

    func testParseLockedAndPrunableReasons() throws {
        let output = [
            "worktree /Users/test/Locked",
            "HEAD 1111111111111111111111111111111111111111",
            "branch refs/heads/locked",
            "locked active build",
            "",
            "worktree /Users/test/Missing",
            "HEAD 2222222222222222222222222222222222222222",
            "branch refs/heads/missing",
            "prunable worktree directory does not exist"
        ].joined(separator: "\n")

        let worktrees = try parser.parse(output)

        XCTAssertEqual(worktrees[0].lockReason, "active build")
        XCTAssertNil(worktrees[0].pruneReason)
        XCTAssertEqual(worktrees[1].pruneReason, "worktree directory does not exist")
        XCTAssertNil(worktrees[1].lockReason)
    }

    func testParseEmptyOutput() throws {
        XCTAssertEqual(try parser.parse(""), [])
    }

    func testParseWindowsLineEndings() throws {
        let output = [
            "worktree /Users/test/Project",
            "HEAD 1111111111111111111111111111111111111111",
            "branch refs/heads/main",
            "",
            "worktree /Users/test/Feature",
            "HEAD 2222222222222222222222222222222222222222",
            "branch refs/heads/feature"
        ].joined(separator: "\r\n")

        let worktrees = try parser.parse(output)

        XCTAssertEqual(worktrees.map(\.path), ["/Users/test/Project", "/Users/test/Feature"])
        XCTAssertEqual(worktrees.map(\.branchName), ["main", "feature"])
    }

    func testParseLockedAndPrunableWithoutReasons() throws {
        let output = [
            "worktree /Users/test/Project",
            "HEAD 1111111111111111111111111111111111111111",
            "locked",
            "",
            "worktree /Users/test/Missing",
            "HEAD 2222222222222222222222222222222222222222",
            "prunable"
        ].joined(separator: "\n")

        let worktrees = try parser.parse(output)

        XCTAssertEqual(worktrees[0].lockReason, "")
        XCTAssertEqual(worktrees[1].pruneReason, "")
    }

    func testMissingPathThrows() {
        let output = [
            "HEAD 1111111111111111111111111111111111111111",
            "branch refs/heads/main"
        ].joined(separator: "\n")

        XCTAssertThrowsError(try parser.parse(output)) { error in
            XCTAssertEqual(error as? GitWorktreeParserError, .missingPath(recordIndex: 0))
        }
    }

    func testMissingHeadThrows() {
        let output = [
            "worktree /Users/test/Project",
            "branch refs/heads/main"
        ].joined(separator: "\n")

        XCTAssertThrowsError(try parser.parse(output)) { error in
            XCTAssertEqual(error as? GitWorktreeParserError, .missingHead(recordIndex: 0))
        }
    }
}
