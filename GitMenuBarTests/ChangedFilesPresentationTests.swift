@testable import GitMenuBar
import XCTest

final class ChangedFilesPresentationTests: XCTestCase {
    func testShouldAutoExpandWhenWithinFileAndLineBudgets() {
        XCTAssertTrue(
            ChangedFilesPresentation.shouldAutoExpandChangedFiles(
                fileCount: 5,
                totalChangedLines: 200,
                isPrimaryContext: true
            )
        )
    }

    func testShouldNotAutoExpandWhenNotPrimaryContext() {
        XCTAssertFalse(
            ChangedFilesPresentation.shouldAutoExpandChangedFiles(
                fileCount: 1,
                totalChangedLines: 1,
                isPrimaryContext: false
            )
        )
    }

    func testShouldNotAutoExpandWhenFileCountExceedsLimit() {
        XCTAssertFalse(
            ChangedFilesPresentation.shouldAutoExpandChangedFiles(
                fileCount: 6,
                totalChangedLines: 10,
                isPrimaryContext: true
            )
        )
    }

    func testShouldNotAutoExpandWhenLineCountExceedsLimit() {
        XCTAssertFalse(
            ChangedFilesPresentation.shouldAutoExpandChangedFiles(
                fileCount: 3,
                totalChangedLines: 201,
                isPrimaryContext: true
            )
        )
    }

    func testSummarizeChangedFileScopesOrdersByCountThenFirstSeen() {
        let paths = [
            "Sources/App.swift",
            "Sources/Utils/Helper.swift",
            "Tests/AppTests.swift",
            "README.md"
        ]

        let scopes = ChangedFilesPresentation.summarizeChangedFileScopes(paths: paths)

        XCTAssertEqual(
            scopes,
            [
                ChangedFilesScopeSummary(label: "Sources", fileCount: 2),
                ChangedFilesScopeSummary(label: "Tests", fileCount: 1),
                ChangedFilesScopeSummary(label: "root", fileCount: 1)
            ]
        )
    }

    func testSummarizeChangedFileScopesRespectsLimit() {
        let paths = [
            "A/one.swift",
            "B/two.swift",
            "C/three.swift",
            "D/four.swift",
            "E/five.swift"
        ]

        let scopes = ChangedFilesPresentation.summarizeChangedFileScopes(paths: paths, limit: 2)

        XCTAssertEqual(scopes.count, 2)
        XCTAssertEqual(scopes.map(\.label), ["A", "B"])
    }

    func testSelectChangedFilePreviewPrefersDistinctScopes() {
        let paths = [
            "Sources/App.swift",
            "Sources/Utils/Helper.swift",
            "Tests/AppTests.swift",
            "README.md"
        ]

        let preview = ChangedFilesPresentation.selectChangedFilePreview(paths: paths)

        XCTAssertEqual(
            preview,
            ["Sources/App.swift", "Tests/AppTests.swift", "README.md"]
        )
    }

    func testSelectChangedFilePreviewFillsRemainingSlotsFromSameScope() {
        let paths = [
            "Sources/App.swift",
            "Sources/Utils/Helper.swift",
            "Sources/Models/Item.swift"
        ]

        let preview = ChangedFilesPresentation.selectChangedFilePreview(paths: paths, limit: 3)

        XCTAssertEqual(
            preview,
            ["Sources/App.swift", "Sources/Utils/Helper.swift", "Sources/Models/Item.swift"]
        )
    }

    func testChangedFileNameReturnsLastPathComponent() {
        XCTAssertEqual(
            ChangedFilesPresentation.changedFileName(path: "GitMenuBar/Pages/MainMenu/View.swift"),
            "View.swift"
        )
        XCTAssertEqual(ChangedFilesPresentation.changedFileName(path: "README.md"), "README.md")
    }
}
