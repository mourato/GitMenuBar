@testable import GitMenuBar
import XCTest

final class GitStashServiceTests: XCTestCase {
    func testParseEmptyListReturnsEmptyArray() {
        XCTAssertEqual(GitStashService.parseStashList(""), [])
        XCTAssertEqual(GitStashService.parseStashList("   \n"), [])
    }

    func testParseValidNULDelimitedRecords() {
        let output = [
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\0stash@{0}\0WIP on main: first\0100\0",
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\0stash@{1}\0On feature/x: second\0200\0"
        ].joined(separator: "\n")

        let stashes = GitStashService.parseStashList(output)
        XCTAssertEqual(stashes.count, 2)
        XCTAssertEqual(stashes[0].hash, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(stashes[0].displayRef, "stash@{0}")
        XCTAssertEqual(stashes[0].branchName, "main")
        XCTAssertEqual(stashes[0].createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(stashes[1].branchName, "feature/x")
        XCTAssertEqual(stashes[1].id, stashes[1].hash)
    }

    func testParseSkipsMalformedRecords() {
        let output = [
            "not-a-hash\0stash@{0}\0WIP on main: bad\0100\0",
            "cccccccccccccccccccccccccccccccccccccccc\0not-a-ref\0WIP on main: bad-ref\0100\0",
            "incomplete",
            "dddddddddddddddddddddddddddddddddddddddd\0stash@{2}\0WIP on topic: good\0300\0"
        ].joined(separator: "\n")

        let stashes = GitStashService.parseStashList(output)
        XCTAssertEqual(stashes.map(\.hash), ["dddddddddddddddddddddddddddddddddddddddd"])
    }

    func testParsePreservesReorderedRefs() {
        let output = [
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\0stash@{0}\0On older: second\0200\0",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\0stash@{1}\0On newer: first\0100\0"
        ].joined(separator: "\n")
        let stashes = GitStashService.parseStashList(output)
        XCTAssertEqual(stashes.map(\.hash), [
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ])
    }

    func testApplyKeepsSelectedHashAndDropRemovesOnlyThatHash() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try writeFile("first\n", named: "note.txt", in: repoURL)
        try runGit(["add", "note.txt"], in: repoURL)
        try runGit(["commit", "-m", "feat: note"], in: repoURL)

        try writeFile("stash-a\n", named: "note.txt", in: repoURL)
        try runGit(["stash", "push", "-m", "stash-a"], in: repoURL)
        try writeFile("stash-b\n", named: "note.txt", in: repoURL)
        try runGit(["stash", "push", "-m", "stash-b"], in: repoURL)

        let service = GitStashService(commandRunner: GitCommandRunner())
        let listed = service.listStashes(in: repoURL.path)
        XCTAssertEqual(listed.count, 2)
        let older = try XCTUnwrap(listed.last)

        let applyResult = service.applyStash(hash: older.hash, in: repoURL.path)
        if case let .failure(error) = applyResult {
            XCTFail("Apply should succeed: \(error.localizedDescription)")
        }
        let afterApply = service.listStashes(in: repoURL.path).map(\.hash)
        XCTAssertTrue(afterApply.contains(older.hash))

        try writeFile("stash-c\n", named: "extra.txt", in: repoURL)
        try runGit(["add", "extra.txt"], in: repoURL)
        try runGit(["stash", "push", "-m", "stash-c"], in: repoURL)

        let dropResult = service.dropStash(hash: older.hash, in: repoURL.path)
        if case let .failure(error) = dropResult {
            XCTFail("Drop should succeed: \(error.localizedDescription)")
        }
        let remaining = service.listStashes(in: repoURL.path).map(\.hash)
        XCTAssertFalse(remaining.contains(older.hash))
        XCTAssertEqual(remaining.count, 2)
    }

    func testFailedApplyRetainsStash() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try writeFile("base\n", named: "note.txt", in: repoURL)
        try runGit(["add", "note.txt"], in: repoURL)
        try runGit(["commit", "-m", "feat: note"], in: repoURL)

        try writeFile("stashed\n", named: "note.txt", in: repoURL)
        try runGit(["stash", "push", "-m", "keep-me"], in: repoURL)
        try writeFile("conflicting\n", named: "note.txt", in: repoURL)

        let service = GitStashService(commandRunner: GitCommandRunner())
        let hash = try XCTUnwrap(service.listStashes(in: repoURL.path).first?.hash)
        let result = service.applyStash(hash: hash, in: repoURL.path)
        if case .success = result {
            XCTFail("Conflicting apply should fail")
        }
        XCTAssertEqual(service.listStashes(in: repoURL.path).map(\.hash), [hash])
    }

    private func writeFile(_ contents: String, named name: String, in repoURL: URL) throws {
        try contents.write(to: repoURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}
