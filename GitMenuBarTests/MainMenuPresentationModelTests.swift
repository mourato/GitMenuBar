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

    func testShowProjectCleanupUpdatesRoute() {
        let model = MainMenuPresentationModel()

        model.showProjectCleanup()

        XCTAssertEqual(model.route, .projectCleanup)
    }

    func testShowMainExitsProjectCleanup() {
        let model = MainMenuPresentationModel()

        model.showProjectCleanup()
        model.showMain()

        XCTAssertEqual(model.route, .main)
    }

    func testProjectCleanupRouteRoundTrip() {
        let model = MainMenuPresentationModel()

        model.showProjectCleanup()
        XCTAssertEqual(model.route, .projectCleanup)

        model.showMain()
        XCTAssertEqual(model.route, .main)
    }

    func testRequestCommandPalettePresentationIncrementsToken() {
        let model = MainMenuPresentationModel()

        model.requestCommandPalettePresentation()
        model.requestCommandPalettePresentation()

        XCTAssertEqual(model.showCommandPaletteToken, 2)
    }

    func testRequestRepositoryOptionsPresentationIncrementsToken() {
        let model = MainMenuPresentationModel()

        model.requestRepositoryOptionsPresentation()
        model.requestRepositoryOptionsPresentation()

        XCTAssertEqual(model.showRepositoryOptionsToken, 2)
    }

    func testRefreshStateTransitions() {
        let model = MainMenuPresentationModel()

        let generation = model.startRefresh()
        XCTAssertEqual(model.refreshState, .refreshing)
        XCTAssertTrue(model.isFastLoading)
        XCTAssertTrue(model.isDetailLoading)

        model.markFastPhaseReady(generation: generation)
        XCTAssertFalse(model.isFastLoading)
        XCTAssertTrue(model.isDetailLoading)

        model.finishRefresh(generation: generation)
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertEqual(model.refreshState, .idle)

        model.failRefresh(message: "failed")
        XCTAssertEqual(model.refreshState, .failed(message: "failed"))

        model.clearRefreshError()
        XCTAssertEqual(model.refreshState, .idle)
    }

    func testStaleRefreshCannotFinishNewerRefresh() {
        let model = MainMenuPresentationModel()

        let firstGeneration = model.startRefresh()
        let secondGeneration = model.startRefresh()
        model.finishRefresh(generation: firstGeneration)

        XCTAssertEqual(model.refreshState, .refreshing)
        XCTAssertTrue(model.isFastLoading)
        XCTAssertTrue(model.isDetailLoading)

        model.markFastPhaseReady(generation: secondGeneration)
        model.finishRefresh(generation: secondGeneration)
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
