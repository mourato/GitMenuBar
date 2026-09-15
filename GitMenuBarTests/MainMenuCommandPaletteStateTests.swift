@testable import GitMenuBar
import XCTest

@MainActor
final class MainMenuCommandPaletteStateTests: XCTestCase {
    func testOpenResetsQueryAndPresents() {
        let state = MainMenuCommandPaletteState()
        state.query = "stale"
        state.selectedItemID = "stale"

        state.open(defaultSelectionID: "action.commit")

        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.query, "")
        XCTAssertEqual(state.selectedItemID, "action.commit")
    }

    func testCloseResetsAllFields() {
        let state = MainMenuCommandPaletteState()
        state.open(defaultSelectionID: "action.commit")

        state.close()

        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state.query, "")
        XCTAssertNil(state.selectedItemID)
    }

    func testClaimRejectsStaleTokens() {
        let state = MainMenuCommandPaletteState()

        XCTAssertTrue(state.claimPresentationRequest(2))
        XCTAssertFalse(state.claimPresentationRequest(2))
        XCTAssertFalse(state.claimPresentationRequest(1))
        XCTAssertTrue(state.claimPresentationRequest(3))
    }
}
