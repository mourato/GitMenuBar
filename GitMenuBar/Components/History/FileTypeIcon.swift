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
    case sourceCode
    case web
    case stylesheet
    case package
    case xcodeProject
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

private struct FileTypeIconMapping {
    let kind: FileTypeIconKind
    let artwork: FileTypeIconArtwork
    let fallbackSymbolName: String
}

enum FileTypeIcon {
    static func resolve(for path: String) -> FileTypeIconDescriptor {
        let fileName = (path as NSString).lastPathComponent
        let normalizedFileName = fileName.lowercased()
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        if let mapping = exactFileMappings[normalizedFileName] ?? extensionMappings[fileExtension] {
            return descriptor(for: mapping)
        }

        return descriptor(for: .generic, artwork: .pierre("default"), fallbackSymbolName: "doc")
    }

    static func directoryIconName(isExpanded: Bool) -> String {
        isExpanded ? "folder.fill" : "folder"
    }

    private static let exactFileMappings: [String: FileTypeIconMapping] = [
        "makefile": configMapping,
        "dockerfile": configMapping,
        ".gitignore": configMapping,
        ".gitattributes": configMapping,
        ".swiftformat": configMapping,
        ".swiftlint.yml": configMapping,
        "package.resolved": lockfileMapping,
        "package-lock.json": lockfileMapping,
        "yarn.lock": lockfileMapping,
        "pnpm-lock.yaml": lockfileMapping,
        "poetry.lock": lockfileMapping,
        "gemfile.lock": lockfileMapping,
        "package.json": packageMapping,
        "gemfile": packageMapping,
        "podfile": packageMapping,
        "cartfile": packageMapping
    ]

    private static let extensionMappings: [String: FileTypeIconMapping] = [
        "swift": FileTypeIconMapping(kind: .swift, artwork: .pierre("swift"), fallbackSymbolName: "swift"),
        "md": FileTypeIconMapping(kind: .markdown, artwork: .pierre("markdown"), fallbackSymbolName: "doc.richtext"),
        "markdown": FileTypeIconMapping(kind: .markdown, artwork: .pierre("markdown"), fallbackSymbolName: "doc.richtext"),
        "json": FileTypeIconMapping(kind: .json, artwork: .pierre("json"), fallbackSymbolName: "curlybraces"),
        "yaml": FileTypeIconMapping(kind: .yaml, artwork: .pierre("json"), fallbackSymbolName: "curlybraces"),
        "yml": FileTypeIconMapping(kind: .yaml, artwork: .pierre("json"), fallbackSymbolName: "curlybraces"),
        "sh": FileTypeIconMapping(kind: .shell, artwork: .pierre("bash"), fallbackSymbolName: "terminal"),
        "bash": FileTypeIconMapping(kind: .shell, artwork: .pierre("bash"), fallbackSymbolName: "terminal"),
        "zsh": FileTypeIconMapping(kind: .shell, artwork: .pierre("bash"), fallbackSymbolName: "terminal")
    ]
    .merging(mappings(for: imageExtensions, to: imageMapping)) { current, _ in current }
    .merging(mappings(for: configExtensions, to: configMapping)) { current, _ in current }
    .merging(mappings(for: uiResourceExtensions, to: uiResourceMapping)) { current, _ in current }
    .merging(mappings(for: webExtensions, to: webMapping)) { current, _ in current }
    .merging(mappings(for: stylesheetExtensions, to: stylesheetMapping)) { current, _ in current }
    .merging(mappings(for: sourceCodeExtensions, to: sourceCodeMapping)) { current, _ in current }
    .merging(mappings(for: xcodeProjectExtensions, to: xcodeProjectMapping)) { current, _ in current }

    private static let colorPairs: [FileTypeIconKind: FileTypeIconColorPair] = [
        .swift: colorPair(light: 0xD47628, dark: 0xFFA359),
        .markdown: colorPair(light: 0x199F43, dark: 0x5ECC71),
        .json: colorPair(light: 0xD47628, dark: 0xFFA359),
        .yaml: colorPair(light: 0xD52C36, dark: 0xFF6762),
        .shell: colorPair(light: 0x199F43, dark: 0x5ECC71),
        .image: colorPair(light: 0xD32A61, dark: 0xFF678D),
        .config: colorPair(light: 0x84848A, dark: 0xADADB1),
        .uiResource: colorPair(light: 0x84848A, dark: 0xADADB1),
        .sourceCode: colorPair(light: 0x5967D8, dark: 0x93A4FF),
        .web: colorPair(light: 0x1A83A8, dark: 0x62C3E6),
        .stylesheet: colorPair(light: 0x2563C9, dark: 0x73A7FF),
        .package: colorPair(light: 0x8B6F2A, dark: 0xD8B65A),
        .xcodeProject: colorPair(light: 0x3E7DBD, dark: 0x7DB7F2),
        .generic: colorPair(light: 0x84848A, dark: 0xADADB1)
    ]

    private static let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "pdf"]
    private static let configExtensions = ["plist", "xcconfig", "entitlements", "toml", "ini", "env"]
    private static let uiResourceExtensions = ["xcassets", "storyboard", "xib", "strings"]
    private static let webExtensions = ["html", "htm"]
    private static let stylesheetExtensions = ["css", "scss", "sass", "less"]
    private static let sourceCodeExtensions = [
        "js", "jsx", "ts", "tsx", "mjs", "cjs", "py", "go", "rb", "java", "kt", "kts", "rs", "c", "cc", "cpp",
        "cxx", "h", "hpp", "m", "mm"
    ]
    private static let xcodeProjectExtensions = ["pbxproj", "xcscheme", "xcworkspacedata", "xcodeproj", "xcworkspace", "resolved"]

    private static let configMapping = FileTypeIconMapping(
        kind: .config,
        artwork: .pierre("default"),
        fallbackSymbolName: "doc.badge.gearshape"
    )
    private static let imageMapping = FileTypeIconMapping(kind: .image, artwork: .pierre("image"), fallbackSymbolName: "photo")
    private static let uiResourceMapping = FileTypeIconMapping(
        kind: .uiResource,
        artwork: .pierre("default"),
        fallbackSymbolName: "square.grid.2x2"
    )
    private static let sourceCodeMapping = FileTypeIconMapping(
        kind: .sourceCode,
        artwork: .system("curlybraces"),
        fallbackSymbolName: "curlybraces"
    )
    private static let webMapping = FileTypeIconMapping(kind: .web, artwork: .system("globe"), fallbackSymbolName: "globe")
    private static let stylesheetMapping = FileTypeIconMapping(
        kind: .stylesheet,
        artwork: .system("number"),
        fallbackSymbolName: "number"
    )
    private static let packageMapping = FileTypeIconMapping(
        kind: .package,
        artwork: .system("shippingbox"),
        fallbackSymbolName: "shippingbox"
    )
    private static let lockfileMapping = FileTypeIconMapping(kind: .package, artwork: .system("lock"), fallbackSymbolName: "lock")
    private static let xcodeProjectMapping = FileTypeIconMapping(
        kind: .xcodeProject,
        artwork: .system("hammer"),
        fallbackSymbolName: "hammer"
    )

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

    private static func descriptor(for mapping: FileTypeIconMapping) -> FileTypeIconDescriptor {
        descriptor(
            for: mapping.kind,
            artwork: mapping.artwork,
            fallbackSymbolName: mapping.fallbackSymbolName
        )
    }

    private static func colorPair(for kind: FileTypeIconKind) -> FileTypeIconColorPair {
        colorPairs[kind] ?? colorPair(light: 0x84848A, dark: 0xADADB1)
    }

    private static func mappings(
        for extensions: [String],
        to mapping: FileTypeIconMapping
    ) -> [String: FileTypeIconMapping] {
        Dictionary(uniqueKeysWithValues: extensions.map { ($0, mapping) })
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
