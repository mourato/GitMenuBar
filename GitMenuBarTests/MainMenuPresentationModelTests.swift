@testable import GitMenuBar
import XCTest

@MainActor
final class MainMenuPresentationModelTests: XCTestCase {
    func testPrepareForPresentationRequestsCommitFocusForMainRoute() {
        let model = MainMenuPresentationModel()

        model.prepareForPresentation(route: .main, requestCommitFocus: true)

        XCTAssertEqual(model.route, .main)
        XCTAssertEqual(model.focusCommitFieldToken, 1)
    }

    func testPrepareForPresentationClearsCreateRepoSuggestionWhenShowingCreateRepo() {
        let model = MainMenuPresentationModel()

        model.suggestCreateRepo(path: "/tmp/repo")
        model.prepareForPresentation(route: .createRepo(path: "/tmp/repo"), requestCommitFocus: false)

        XCTAssertEqual(model.route, .createRepo(path: "/tmp/repo"))
        XCTAssertNil(model.createRepoSuggestionPath)
    }

    func testShowMainCanRequestFocus() {
        let model = MainMenuPresentationModel()

        model.showMain(requestCommitFocus: true)

        XCTAssertEqual(model.route, .main)
        XCTAssertEqual(model.focusCommitFieldToken, 1)
    }

    func testRefreshStateTransitions() {
        let model = MainMenuPresentationModel()

        model.startRefresh()
        XCTAssertEqual(model.refreshState, .refreshing)

        model.failRefresh(message: "failed")
        XCTAssertEqual(model.refreshState, .failed(message: "failed"))

        model.clearRefreshError()
        XCTAssertEqual(model.refreshState, .idle)
    }

    func testCreateRepoSuggestionRoundTrip() {
        let model = MainMenuPresentationModel()

        model.suggestCreateRepo(path: "/tmp/repo")
        XCTAssertEqual(model.createRepoSuggestionPath, "/tmp/repo")

        model.clearCreateRepoSuggestion()
        XCTAssertNil(model.createRepoSuggestionPath)
    }
}
