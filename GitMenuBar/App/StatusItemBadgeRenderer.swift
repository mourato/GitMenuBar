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

    static func makeCompositeImage(
        baseStatusImage: NSImage?,
        usageImage: NSImage?,
        iconSize: NSSize
    ) -> NSImage? {
        guard let baseStatusImage else { return usageImage }
        let usageWidth = usageImage?.size.width ?? 0
        let gap: CGFloat = usageImage == nil ? 0 : 6
        let image = NSImage(size: NSSize(width: iconSize.width + gap + usageWidth, height: max(iconSize.height, usageImage?.size.height ?? 0)))

        image.lockFocus()
        let iconRect = NSRect(
            x: 0,
            y: (image.size.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        baseStatusImage.draw(in: iconRect)
        if let usageImage {
            let usageRect = NSRect(
                x: iconSize.width + gap,
                y: (image.size.height - usageImage.size.height) / 2,
                width: usageImage.size.width,
                height: usageImage.size.height
            )
            usageImage.draw(in: usageRect)
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
