@testable import GitMenuBar
import XCTest

final class DiffTreeBuilderTests: XCTestCase {
    func testBuildsFlatFilesAtRepoRoot() {
        let inputs = [
            DiffTreeFileInput(path: "README.md", stat: DiffTreeStat(additions: 1, deletions: 0)),
            DiffTreeFileInput(path: "Package.swift", stat: DiffTreeStat(additions: 2, deletions: 1))
        ]

        let tree = DiffTreeBuilder.buildDiffTree(inputs)

        XCTAssertEqual(tree.count, 2)
        XCTAssertEqual(
            tree,
            [
                .file(name: "Package.swift", path: "Package.swift", stat: DiffTreeStat(additions: 2, deletions: 1)),
                .file(name: "README.md", path: "README.md", stat: DiffTreeStat(additions: 1, deletions: 0))
            ]
        )
    }

    func testAggregatesDirectoryStatsForNestedPaths() {
        let inputs = [
            DiffTreeFileInput(path: "Sources/App.swift", stat: DiffTreeStat(additions: 10, deletions: 2)),
            DiffTreeFileInput(path: "Sources/Utils/Helper.swift", stat: DiffTreeStat(additions: 3, deletions: 1))
        ]

        let tree = DiffTreeBuilder.buildDiffTree(inputs)

        XCTAssertEqual(tree.count, 1)
        guard case let .directory(name, path, stat, children) = tree[0] else {
            return XCTFail("Expected a single directory node")
        }

        XCTAssertEqual(name, "Sources")
        XCTAssertEqual(path, "Sources")
        XCTAssertEqual(stat, DiffTreeStat(additions: 13, deletions: 3))
        XCTAssertEqual(children.count, 2)

        guard case let .directory(utilsName, utilsPath, utilsStat, utilsChildren) = children[0] else {
            return XCTFail("Expected Utils directory node")
        }
        XCTAssertEqual(utilsName, "Utils")
        XCTAssertEqual(utilsPath, "Sources/Utils")
        XCTAssertEqual(utilsStat, DiffTreeStat(additions: 3, deletions: 1))
        XCTAssertEqual(utilsChildren.count, 1)

        guard case let .file(appName, appPath, appStat) = children[1] else {
            return XCTFail("Expected App.swift file node")
        }
        XCTAssertEqual(appName, "App.swift")
        XCTAssertEqual(appPath, "Sources/App.swift")
        XCTAssertEqual(appStat, DiffTreeStat(additions: 10, deletions: 2))
    }

    func testCompactsSingleChildDirectoryChains() {
        let inputs = [
            DiffTreeFileInput(
                path: "GitMenuBar/Pages/MainMenu/View.swift",
                stat: DiffTreeStat(additions: 4, deletions: 0)
            )
        ]

        let tree = DiffTreeBuilder.buildDiffTree(inputs)

        XCTAssertEqual(tree.count, 1)
        guard case let .directory(name, path, stat, children) = tree[0] else {
            return XCTFail("Expected compacted directory node")
        }

        XCTAssertEqual(name, "GitMenuBar/Pages/MainMenu")
        XCTAssertEqual(path, "GitMenuBar/Pages/MainMenu")
        XCTAssertEqual(stat, DiffTreeStat(additions: 4, deletions: 0))
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(
            children[0],
            .file(
                name: "View.swift",
                path: "GitMenuBar/Pages/MainMenu/View.swift",
                stat: DiffTreeStat(additions: 4, deletions: 0)
            )
        )
    }

    func testIgnoresMixedSeparatorsAndEmptySegments() {
        let inputs = [
            DiffTreeFileInput(path: "Sources\\App.swift", stat: DiffTreeStat(additions: 1, deletions: 0)),
            DiffTreeFileInput(path: "//Sources//Edited.swift", stat: DiffTreeStat(additions: 2, deletions: 0))
        ]

        let tree = DiffTreeBuilder.buildDiffTree(inputs)

        XCTAssertEqual(tree.count, 1)
        guard case let .directory(_, _, stat, children) = tree[0] else {
            return XCTFail("Expected Sources directory node")
        }

        XCTAssertEqual(stat, DiffTreeStat(additions: 3, deletions: 0))
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(
            children[0],
            .file(name: "App.swift", path: "Sources/App.swift", stat: DiffTreeStat(additions: 1, deletions: 0))
        )
        XCTAssertEqual(
            children[1],
            .file(name: "Edited.swift", path: "Sources/Edited.swift", stat: DiffTreeStat(additions: 2, deletions: 0))
        )
    }

    func testSortsDirectoriesAndFilesWithNumericAwareOrdering() {
        let inputs = [
            DiffTreeFileInput(path: "item10.txt", stat: DiffTreeStat(additions: 1, deletions: 0)),
            DiffTreeFileInput(path: "item2.txt", stat: DiffTreeStat(additions: 1, deletions: 0)),
            DiffTreeFileInput(path: "Sources/View.swift", stat: DiffTreeStat(additions: 1, deletions: 0)),
            DiffTreeFileInput(path: "Models/Item.swift", stat: DiffTreeStat(additions: 1, deletions: 0))
        ]

        let tree = DiffTreeBuilder.buildDiffTree(inputs)

        XCTAssertEqual(tree.map(nodeName), ["Models", "Sources", "item2.txt", "item10.txt"])
    }

    func testSummarizeDiffTreeStatsTotalsNonNilStats() {
        let inputs = [
            DiffTreeFileInput(path: "A.swift", stat: DiffTreeStat(additions: 5, deletions: 2)),
            DiffTreeFileInput(path: "B.swift", stat: nil),
            DiffTreeFileInput(path: "C.swift", stat: DiffTreeStat(additions: 1, deletions: 3))
        ]

        XCTAssertEqual(
            DiffTreeBuilder.summarizeDiffTreeStats(inputs),
            DiffTreeStat(additions: 6, deletions: 5)
        )
    }

    private func nodeName(_ node: DiffTreeNode) -> String {
        switch node {
        case let .directory(name, _, _, _):
            return name
        case let .file(name, _, _):
            return name
        }
    }
}
