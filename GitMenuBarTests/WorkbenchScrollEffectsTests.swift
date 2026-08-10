import CoreGraphics
@testable import GitMenuBar
import XCTest

final class WorkbenchScrollEffectsTests: XCTestCase {
    func testContentThatFitsIsNotScrollable() {
        let metrics = WorkbenchEdgeDissolveMetrics(contentOffset: 0, contentHeight: 100, containerHeight: 100, topInset: 0, bottomInset: 0)
        XCTAssertFalse(metrics.isScrollable)
    }

    func testContentThatExceedsViewportIsScrollable() {
        let metrics = WorkbenchEdgeDissolveMetrics(contentOffset: 0, contentHeight: 102, containerHeight: 100, topInset: 0, bottomInset: 0)
        XCTAssertTrue(metrics.isScrollable)
    }

    func testDistancesClampAtBounds() {
        let metrics = WorkbenchEdgeDissolveMetrics(contentOffset: -20, contentHeight: 300, containerHeight: 100, topInset: 0, bottomInset: 0)
        XCTAssertEqual(metrics.topDistance, 0)
        XCTAssertEqual(metrics.bottomDistance, 220)
    }

    func testThumbStaysWithinTrackAndUsesMinimumHeight() {
        let metrics = WorkbenchScrollbarMetrics(contentOffset: 10000, contentHeight: 10000, containerHeight: 100, topInset: 0)
        let trackHeight: CGFloat = 200
        let thumbHeight = metrics.thumbHeight(in: trackHeight)
        let thumbOffset = metrics.thumbOffset(in: trackHeight)
        XCTAssertEqual(thumbHeight, WorkbenchMetrics.scrollbarMinimumThumbHeight)
        XCTAssertGreaterThanOrEqual(thumbOffset, WorkbenchMetrics.scrollbarInset)
        XCTAssertLessThanOrEqual(thumbOffset + thumbHeight, WorkbenchMetrics.scrollbarInset + trackHeight)
    }
}
