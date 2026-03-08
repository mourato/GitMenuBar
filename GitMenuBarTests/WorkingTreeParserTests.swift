@testable import GitMenuBar
import XCTest

final class WorkingTreeParserTests: XCTestCase {
    private let parser = WorkingTreeParser(runner: GitCommandRunner())

    func testParsePorcelainStatusSplitsStagedAndChangedFiles() {
        let output = [
            "M  Sources/App.swift",
            " M Sources/Edited.swift",
            "?? Sources/NewFile.swift",
            "R  Sources/Old.swift -> Sources/New.swift"
        ].joined(separator: "\n")

        let status = parser.parsePorcelainStatus(output)

        XCTAssertEqual(status.stagedStatuses["Sources/App.swift"], .modified)
        XCTAssertEqual(status.changedStatuses["Sources/Edited.swift"], .modified)
        XCTAssertEqual(status.changedStatuses["Sources/NewFile.swift"], .untracked)
        XCTAssertEqual(status.stagedStatuses["Sources/New.swift"], .modified)
        XCTAssertTrue(status.untrackedPaths.contains("Sources/NewFile.swift"))
    }

    func testParseNumstatMapsLineDiffsPerPath() {
        let output = [
            "10\t2\tSources/App.swift",
            "3\t0\tSources/NewFile.swift"
        ].joined(separator: "\n")

        let numstat = parser.parseNumstat(output)

        XCTAssertEqual(numstat["Sources/App.swift"], LineDiffStats(added: 10, removed: 2))
        XCTAssertEqual(numstat["Sources/NewFile.swift"], LineDiffStats(added: 3, removed: 0))
    }
}
