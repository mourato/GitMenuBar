import AppKit
@testable import GitMenuBar
import XCTest

final class StatusItemBadgeRendererTests: XCTestCase {
    func testCompositeImagePreservesTemplateRenderingWithoutBadge() {
        let iconSize = NSSize(width: 18, height: 18)

        let image = StatusItemBadgeRenderer.makeCompositeImage(
            baseStatusImage: makeTemplateImage(size: iconSize),
            usageImage: nil,
            iconSize: iconSize
        )

        XCTAssertEqual(image?.size, iconSize)
        XCTAssertEqual(image?.isTemplate, true)
    }

    func testCompositeImageKeepsUsageStripAsTemplate() {
        let iconSize = NSSize(width: 18, height: 18)
        let usageSize = NSSize(width: 18, height: 18)

        let image = StatusItemBadgeRenderer.makeCompositeImage(
            baseStatusImage: makeTemplateImage(size: iconSize),
            usageImage: makeTemplateImage(size: usageSize),
            iconSize: iconSize
        )

        XCTAssertEqual(image?.size, NSSize(width: 42, height: 18))
        XCTAssertEqual(image?.isTemplate, true)
    }

    func testCompositeImageReturnsUsageImageWithoutBaseImage() {
        let usageImage = makeTemplateImage(size: NSSize(width: 18, height: 18))
        let image = StatusItemBadgeRenderer.makeCompositeImage(
            baseStatusImage: nil,
            usageImage: usageImage,
            iconSize: NSSize(width: 18, height: 18)
        )

        XCTAssertTrue(image === usageImage)
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
