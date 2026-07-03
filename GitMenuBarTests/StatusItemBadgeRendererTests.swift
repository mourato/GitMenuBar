import AppKit
@testable import GitMenuBar
import XCTest

final class StatusItemBadgeRendererTests: XCTestCase {
    func testBadgedImagePreservesSizeAndDisablesTemplateRendering() {
        let iconSize = NSSize(width: 18, height: 18)

        let image = StatusItemBadgeRenderer.makeBadgedImage(
            count: 3,
            baseStatusImage: makeTemplateImage(size: iconSize),
            iconSize: iconSize
        )

        XCTAssertEqual(image?.size, iconSize)
        XCTAssertEqual(image?.isTemplate, false)
    }

    func testBadgedImageSupportsCappedLargeCounts() {
        let iconSize = NSSize(width: 18, height: 18)

        let image = StatusItemBadgeRenderer.makeBadgedImage(
            count: 120,
            baseStatusImage: makeTemplateImage(size: iconSize),
            iconSize: iconSize
        )

        XCTAssertEqual(image?.size, iconSize)
        XCTAssertEqual(image?.isTemplate, false)
    }

    func testBadgedImageReturnsNilWithoutBaseImage() {
        let image = StatusItemBadgeRenderer.makeBadgedImage(
            count: 1,
            baseStatusImage: nil,
            iconSize: NSSize(width: 18, height: 18)
        )

        XCTAssertNil(image)
    }

    private func makeTemplateImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
