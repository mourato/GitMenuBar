@testable import GitMenuBar
import XCTest

final class GitDiffHunkParserTests: XCTestCase {
    func testParsesOrderedHunksAndCounts() {
        let diff = """
        diff --git a/space name.swift b/space name.swift
        --- a/space name.swift
        +++ b/space name.swift
        @@ -1,2 +1,3 @@
         one
        +two
         three
        @@ -8,2 +9,1 @@
         eight
        -nine
        """
        let hunks = GitDiffHunkParser.parse(path: "space name.swift", diff: diff)
        XCTAssertEqual(hunks.map(\.id), ["space name.swift#hunk-1", "space name.swift#hunk-2"])
        XCTAssertEqual(hunks[0].additions, 1)
        XCTAssertEqual(hunks[0].removals, 0)
        XCTAssertEqual(hunks[0].header, "@@ -1,2 +1,3 @@")
        XCTAssertEqual(hunks[1].removals, 1)
    }

    func testRejectsMalformedRecordsWithoutPartialHunks() {
        let diff = """
        diff --git a/a.swift b/a.swift
        --- a/a.swift
        +++ b/a.swift
        @@ malformed
        +bad
        """
        XCTAssertTrue(GitDiffHunkParser.parse(path: "a.swift", diff: diff).isEmpty)
    }
}
