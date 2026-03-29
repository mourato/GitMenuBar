@testable import GitMenuBar
import SwiftUI
import XCTest

final class MainMenuSelectionNavigatorTests: XCTestCase {
    func testMoveSelectionStartsAtFirstItemWhenMovingDownWithoutSelection() {
        let items: [MainMenuSelectableItem] = [
            .stagedFile(path: "a.txt"),
            .unstagedFile(path: "b.txt"),
            .historyCommit(id: "abc123")
        ]

        let selection = MainMenuSelectionNavigator.moveSelection(
            currentSelection: nil,
            items: items,
            direction: .down
        )

        XCTAssertEqual(selection, items.first)
    }

    func testMoveSelectionStartsAtLastItemWhenMovingUpWithoutSelection() {
        let items: [MainMenuSelectableItem] = [
            .stagedFile(path: "a.txt"),
            .unstagedFile(path: "b.txt"),
            .historyCommit(id: "abc123")
        ]

        let selection = MainMenuSelectionNavigator.moveSelection(
            currentSelection: nil,
            items: items,
            direction: .up
        )

        XCTAssertEqual(selection, items.last)
    }

    func testMoveSelectionClampsAtBounds() {
        let items: [MainMenuSelectableItem] = [
            .stagedFile(path: "a.txt"),
            .unstagedFile(path: "b.txt")
        ]

        let downSelection = MainMenuSelectionNavigator.moveSelection(
            currentSelection: items.last,
            items: items,
            direction: .down
        )
        let upSelection = MainMenuSelectionNavigator.moveSelection(
            currentSelection: items.first,
            items: items,
            direction: .up
        )

        XCTAssertEqual(downSelection, items.last)
        XCTAssertEqual(upSelection, items.first)
    }
}
