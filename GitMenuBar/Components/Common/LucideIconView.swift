import AppKit
import SwiftUI

enum LucideIconRenderer {
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()

    static func image(for name: LucideIconName) -> NSImage? {
        let key = name.rawValue as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let url = resourceURL(for: name),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data)
        else {
            return nil
        }
        image.size = NSSize(width: LucideIconView.defaultSize, height: LucideIconView.defaultSize)
        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }

    static func resourceURL(for name: LucideIconName) -> URL? {
        let file = name.rawValue
        if let url = Bundle.main.url(forResource: file, withExtension: "svg") {
            return url
        }
        if let url = Bundle.main.url(forResource: file, withExtension: "svg", subdirectory: "LucideIcons") {
            return url
        }
        return Bundle.main.url(forResource: file, withExtension: "svg", subdirectory: "Resources/LucideIcons")
    }

    static func image(for name: LucideIconName, canvas: CGFloat, glyph: CGFloat) -> NSImage? {
        let key = "\(name.rawValue)@\(Int(canvas))/\(Int(glyph))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = image(for: name) else {
            return nil
        }
        let inset = (canvas - glyph) / 2
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
            source.draw(in: rect.insetBy(dx: inset, dy: inset))
            return true
        }
        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }
}

extension NSImage {
    convenience init?(lucide name: LucideIconName) {
        guard let image = LucideIconRenderer.image(for: name) else {
            return nil
        }
        self.init(size: image.size)
        addRepresentations(image.representations)
        isTemplate = true
    }

    convenience init?(lucide name: LucideIconName, canvas: CGFloat, glyph: CGFloat) {
        guard let image = LucideIconRenderer.image(for: name, canvas: canvas, glyph: glyph) else {
            return nil
        }
        self.init(size: image.size)
        addRepresentations(image.representations)
        isTemplate = true
    }
}

struct LucideIconView: View {
    static let defaultSize: CGFloat = 16

    let name: LucideIconName
    var size: CGFloat = defaultSize

    var body: some View {
        Group {
            if let image = LucideIconRenderer.image(for: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "questionmark")
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Label where Title == Text, Icon == LucideIconView {
    @MainActor
    init(lucide name: LucideIconName, _ title: String, size: CGFloat = LucideIconView.defaultSize) {
        self.init(title: { Text(title) }, icon: { LucideIconView(name: name, size: size) })
    }
}

private struct LucideIconCatalogPreview: View {
    private let columns = [GridItem(.adaptive(minimum: 104))]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Label(lucide: .search, "Search")
                    Label(lucide: .settings, "Settings")
                    Label(lucide: .gitBranch, "main")
                }
                HStack(spacing: 16) {
                    LucideIconView(name: .check, size: 12)
                    LucideIconView(name: .check, size: 16)
                    LucideIconView(name: .check, size: 24)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(LucideIconName.allCases, id: \.rawValue) { name in
                        VStack(spacing: 4) {
                            LucideIconView(name: name)
                            Text(name.rawValue)
                                .font(WorkbenchTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 480)
    }
}

#Preview("Lucide Icons — Light") {
    LucideIconCatalogPreview()
        .preferredColorScheme(.light)
}

#Preview("Lucide Icons — Dark") {
    LucideIconCatalogPreview()
        .preferredColorScheme(.dark)
}
