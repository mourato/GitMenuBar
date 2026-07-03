import AppKit

enum StatusItemBadgeRenderer {
    static func makeBaseStatusImage(iconSize: NSSize) -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon") {
            let resized = image.copy() as? NSImage ?? image
            resized.size = iconSize
            resized.isTemplate = true
            return resized
        }

        let fallback = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: "GitBar")
        fallback?.isTemplate = true
        return fallback
    }

    static func makeBadgedImage(count: Int, baseStatusImage: NSImage?, iconSize: NSSize) -> NSImage? {
        guard let baseStatusImage else { return nil }

        let image = NSImage(size: iconSize)

        image.lockFocus()

        let iconRect = NSRect(x: 0, y: 0, width: iconSize.width, height: iconSize.height)
        baseStatusImage.draw(in: iconRect)

        let displayText = count > 99 ? "99+" : "\(count)"
        let badgeWidth: CGFloat = displayText.count >= 3 ? 17 : (displayText.count == 2 ? 14 : 12)
        let badgeRect = NSRect(x: iconSize.width - badgeWidth + 1, y: iconSize.height - 11, width: badgeWidth, height: 11)

        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 5.5, yRadius: 5.5).fill()

        let fontSize: CGFloat = displayText.count >= 3 ? 6 : 8
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = displayText.size(withAttributes: attributes)
        let textRect = NSRect(
            x: badgeRect.midX - (textSize.width / 2),
            y: badgeRect.midY - (textSize.height / 2),
            width: textSize.width,
            height: textSize.height
        )

        displayText.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
