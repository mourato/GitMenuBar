import AppKit
import SwiftUI

enum FileTypeIconKind: String, Equatable, Sendable {
    case swift
    case markdown
    case json
    case yaml
    case shell
    case image
    case config
    case uiResource
    case generic
}

enum FileTypeIconArtwork: Equatable, Sendable {
    case pierre(String)
    case system(String)
}

struct FileTypeIconDescriptor: Equatable, Sendable {
    let kind: FileTypeIconKind
    let artwork: FileTypeIconArtwork
    let fallbackSymbolName: String
    let lightColor: Color
    let darkColor: Color
    let lightHex: String
    let darkHex: String

    func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? darkColor : lightColor
    }

    func hexColor(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? darkHex : lightHex
    }
}

private struct FileTypeIconColorPair {
    let light: Color
    let dark: Color
    let lightHex: String
    let darkHex: String
}

enum FileTypeIcon {
    static func resolve(for path: String) -> FileTypeIconDescriptor {
        let fileName = (path as NSString).lastPathComponent
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        switch fileExtension {
        case "swift":
            return descriptor(for: .swift, artwork: .pierre("swift"), fallbackSymbolName: "swift")
        case "md", "markdown":
            return descriptor(for: .markdown, artwork: .pierre("markdown"), fallbackSymbolName: "doc.richtext")
        case "json":
            return descriptor(for: .json, artwork: .pierre("json"), fallbackSymbolName: "curlybraces")
        case "yaml", "yml":
            return descriptor(for: .yaml, artwork: .pierre("json"), fallbackSymbolName: "curlybraces")
        case "sh", "bash", "zsh":
            return descriptor(for: .shell, artwork: .pierre("bash"), fallbackSymbolName: "terminal")
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "pdf":
            return descriptor(for: .image, artwork: .pierre("image"), fallbackSymbolName: "photo")
        case "plist", "xcconfig", "entitlements":
            return descriptor(for: .config, artwork: .pierre("default"), fallbackSymbolName: "doc.badge.gearshape")
        case "xcassets", "storyboard", "xib":
            return descriptor(for: .uiResource, artwork: .pierre("default"), fallbackSymbolName: "square.grid.2x2")
        default:
            if fileName.hasPrefix("Makefile") || fileName == "Dockerfile" {
                return descriptor(for: .config, artwork: .pierre("default"), fallbackSymbolName: "doc.badge.gearshape")
            }
            return descriptor(for: .generic, artwork: .pierre("default"), fallbackSymbolName: "doc")
        }
    }

    static func directoryIconName(isExpanded: Bool) -> String {
        isExpanded ? "folder.fill" : "folder"
    }

    private static func descriptor(
        for kind: FileTypeIconKind,
        artwork: FileTypeIconArtwork,
        fallbackSymbolName: String
    ) -> FileTypeIconDescriptor {
        let colors = colorPair(for: kind)
        return FileTypeIconDescriptor(
            kind: kind,
            artwork: artwork,
            fallbackSymbolName: fallbackSymbolName,
            lightColor: colors.light,
            darkColor: colors.dark,
            lightHex: colors.lightHex,
            darkHex: colors.darkHex
        )
    }

    private static func colorPair(for kind: FileTypeIconKind) -> FileTypeIconColorPair {
        switch kind {
        case .swift:
            return colorPair(light: 0xD47628, dark: 0xFFA359)
        case .markdown:
            return colorPair(light: 0x199F43, dark: 0x5ECC71)
        case .json:
            return colorPair(light: 0xD47628, dark: 0xFFA359)
        case .yaml:
            return colorPair(light: 0xD52C36, dark: 0xFF6762)
        case .shell:
            return colorPair(light: 0x199F43, dark: 0x5ECC71)
        case .image:
            return colorPair(light: 0xD32A61, dark: 0xFF678D)
        case .config, .uiResource:
            return colorPair(light: 0x84848A, dark: 0xADADB1)
        case .generic:
            return colorPair(light: 0x84848A, dark: 0xADADB1)
        }
    }

    private static func colorPair(light: UInt32, dark: UInt32) -> FileTypeIconColorPair {
        FileTypeIconColorPair(
            light: hex(light),
            dark: hex(dark),
            lightHex: hexString(light),
            darkHex: hexString(dark)
        )
    }

    private static func hexString(_ value: UInt32) -> String {
        String(format: "#%06X", value)
    }

    private static func hex(_ value: UInt32) -> Color {
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }
}

private enum FileTypeIconSVG {
    static func template(named name: String) -> String? {
        templates[name]
    }

    private static let templates: [String: String] = [
        "swift": """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <path fill="currentColor" d="M9.63 1c6.15 4.35 4.16 9.15 4.16 9.15s1.75
          2.05 1.04 3.85c0 0-.72-1.26-1.93-1.26-1.17 0-1.85 1.26-4.2 1.26C3.47
          14 1 9.46 1 9.46c4.71 3.22 7.93.94 7.93.94C6.8 9.12 2.29 3 2.29 3c3.93
          3.47 5.63 4.39 5.63 4.39-1.01-.87-3.86-5.13-3.86-5.13C6.34 4.66 10.86 8
          10.86 8c1.28-3.7-1.23-7-1.23-7"/>
        </svg>
        """,
        "markdown": """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <path fill="currentColor" d="M1 12V4h2l2 2.5L7 4h2v8H7V7.5l-2 2-2-2V12zm9-3 3 3.5L16 9h-2V4h-2v5z"/>
        </svg>
        """,
        "json": """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <path fill="currentColor" d="M13.25 11.5V9.75a.5.5 0 0 1 .36-.48l.55-.15a1.16
          1.16 0 0 0 0-2.24l-.55-.15a.5.5 0 0 1-.36-.48V4.5a2.5 2.5 0 0 0-2.5-2.5h-.25a.5.5
          0 0 0 0 1h.25a1.5 1.5 0 0 1 1.5 1.5v1.75a1.5 1.5 0 0 0 1.09 1.44l.54.15a.16.16 0 0 1 0
          .32l-.54.15a1.5 1.5 0 0 0-1.09 1.44v1.75a1.5 1.5 0 0 1-1.5 1.5h-.25a.5.5 0 0 0 0 1h.25a2.5
          2.5 0 0 0 2.5-2.5m-10.5 0V9.75a.5.5 0 0 0-.36-.48l-.55-.15a1.16 1.16 0 0 1
          0-2.24l.55-.15a.5.5 0 0 0 .36-.48V4.5A2.5 2.5 0 0 1 5.25 2h.25a.5.5 0 0 1 0 1h-.25a1.5
          1.5 0 0 0-1.5 1.5v1.75a1.5 1.5 0 0 1-1.09 1.44l-.54.15a.16.16 0 0 0 0 .32l.54.15a1.5
          1.5 0 0 1 1.09 1.45v1.74a1.5 1.5 0 0 0 1.5 1.5h.25a.5.5 0 0 1 0 1h-.25a2.5 2.5
          0 0 1-2.5-2.5"/>
        </svg>
        """,
        "bash": """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <path fill="currentColor" d="M8 1C2.24 1 1 2.24 1 8s1.24 7 7 7 7-1.24 7-7-1.24-7-7-7" opacity=".2"/>
          <path fill="currentColor" d="M11.5 11a.5.5 0 0 1 0 1h-3a.5.5 0 0 1 0-1zM7 6.75C7
          6.42 6.64 6 6 6s-1 .42-1 .75q-.01.25.22.41.26.21.89.35.74.14 1.28.53c.37.29.61.7.61
          1.21 0 .87-.68 1.5-1.5 1.7v.55a.5.5 0 0 1-1 0v-.56c-.82-.18-1.5-.82-1.5-1.69a.5.5 0 0
          1 1 0c0 .33.36.75 1 .75s1-.42 1-.75q.01-.25-.22-.41a2 2 0 0 0-.89-.35q-.74-.14-1.28-.53A1.5
          1.5 0 0 1 4 6.75c0-.87.68-1.5 1.5-1.7V4.5a.5.5 0 0 1 1 0v.56c.82.18 1.5.82 1.5 1.69a.5.5
          0 0 1-1 0"/>
        </svg>
        """,
        "image": """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <path fill="currentColor" d="M12.5 2A2.5 2.5 0 0 1 15 4.5v4.67l-4.05-3.54-4.08
          4.08-3-2L1 10.6V4.5A2.5 2.5 0 0 1 3.5 2z" opacity=".3"/>
          <path fill="currentColor" d="M15 10.5v1a2.5 2.5 0 0 1-2.5 2.5h-9a2.5 2.5 0 0 1-2.46-2.04L4
          9l3 2 4-4zm-7-5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0"/>
        </svg>
        """,
        "default": """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <path fill="currentColor" d="M8 1v3a3 3 0 0 0 3 3h3v5.5a2.5 2.5 0 0 1-2.5 2.5h-7A2.5
          2.5 0 0 1 2 12.5v-9A2.5 2.5 0 0 1 4.5 1z" opacity=".4"/>
          <path fill="currentColor" d="M9.5 1a.5.5 0 0 1 .354.146l4 4A.5.5 0 0 1 14 5.5V6h-3a2 2 0 0 1-2-2V1z"/>
        </svg>
        """
    ]
}

private enum FileTypeIconRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for artwork: FileTypeIconArtwork, colorHex: String) -> NSImage? {
        guard case let .pierre(name) = artwork,
              let template = FileTypeIconSVG.template(named: name)
        else {
            return nil
        }

        let cacheKey = "\(name)-\(colorHex)" as NSString
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        let svg = template
            .replacingOccurrences(of: "currentColor", with: colorHex)
            .replacingOccurrences(of: "currentcolor", with: colorHex)

        guard let image = NSImage(data: Data(svg.utf8)) else {
            return nil
        }

        image.size = NSSize(width: 16, height: 16)
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

struct FileTypeIconView: View {
    let path: String

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: FileTypeIconDescriptor {
        FileTypeIcon.resolve(for: path)
    }

    var body: some View {
        icon
            .frame(width: 14, alignment: .center)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = FileTypeIconRenderer.image(
            for: descriptor.artwork,
            colorHex: descriptor.hexColor(for: colorScheme)
        ) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: descriptor.fallbackSymbolName)
                .font(WorkbenchTypography.captionStrong)
                .foregroundStyle(descriptor.color(for: colorScheme))
        }
    }
}

struct FileTypeDirectoryIconView: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: FileTypeIcon.directoryIconName(isExpanded: isExpanded))
            .font(WorkbenchTypography.captionStrong)
            .foregroundStyle(.secondary)
            .frame(width: 14, alignment: .center)
            .accessibilityHidden(true)
    }
}

enum DiffTreeLeadingIcon {
    case file(path: String)
    case directory(isExpanded: Bool)
}

struct DiffTreeLeadingIconView: View {
    let icon: DiffTreeLeadingIcon

    var body: some View {
        switch icon {
        case let .file(path):
            FileTypeIconView(path: path)
        case let .directory(isExpanded):
            FileTypeDirectoryIconView(isExpanded: isExpanded)
        }
    }
}

#Preview("File Type Icons") {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            FileTypeIconView(path: "App.swift")
            Text("App.swift")
        }
        HStack {
            FileTypeIconView(path: "README.md")
            Text("README.md")
        }
        HStack {
            FileTypeIconView(path: "config.json")
            Text("config.json")
        }
        HStack {
            FileTypeDirectoryIconView(isExpanded: false)
            Text("Sources")
        }
    }
    .padding()
}
