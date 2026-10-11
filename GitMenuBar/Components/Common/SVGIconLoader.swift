import AppKit

/// Shared SVG loading for template icons rendered by SwiftUI on the main actor.
@MainActor
enum SVGIconLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(resourceName: String) -> NSImage? {
        let key = resourceName as NSString
        if let image = cache.object(forKey: key) {
            return image
        }
        let url = Bundle.main.url(forResource: resourceName, withExtension: "svg")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "svg", subdirectory: "Resources/ProviderIcons")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "svg", subdirectory: "ProviderIcons")
        guard let url, let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }
}
