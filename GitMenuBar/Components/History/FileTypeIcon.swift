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

struct FileTypeIconDescriptor: Equatable, Sendable {
    let kind: FileTypeIconKind
    let symbolName: String
    let lightColor: Color
    let darkColor: Color

    func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? darkColor : lightColor
    }
}

enum FileTypeIcon {
    static func resolve(for path: String) -> FileTypeIconDescriptor {
        let fileName = (path as NSString).lastPathComponent
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        switch fileExtension {
        case "swift":
            return descriptor(for: .swift, symbolName: "swift")
        case "md", "markdown":
            return descriptor(for: .markdown, symbolName: "doc.richtext")
        case "json":
            return descriptor(for: .json, symbolName: "curlybraces")
        case "yaml", "yml":
            return descriptor(for: .yaml, symbolName: "curlybraces")
        case "sh", "bash", "zsh":
            return descriptor(for: .shell, symbolName: "terminal")
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "pdf":
            return descriptor(for: .image, symbolName: "photo")
        case "plist", "xcconfig", "entitlements":
            return descriptor(for: .config, symbolName: "doc.badge.gearshape")
        case "xcassets", "storyboard", "xib":
            return descriptor(for: .uiResource, symbolName: "square.grid.2x2")
        default:
            if fileName.hasPrefix("Makefile") || fileName == "Dockerfile" {
                return descriptor(for: .config, symbolName: "doc.badge.gearshape")
            }
            return descriptor(for: .generic, symbolName: "doc")
        }
    }

    static func directoryIconName(isExpanded: Bool) -> String {
        isExpanded ? "folder.fill" : "folder"
    }

    private static func descriptor(for kind: FileTypeIconKind, symbolName: String) -> FileTypeIconDescriptor {
        let colors = colorPair(for: kind)
        return FileTypeIconDescriptor(
            kind: kind,
            symbolName: symbolName,
            lightColor: colors.light,
            darkColor: colors.dark
        )
    }

    private static func colorPair(for kind: FileTypeIconKind) -> (light: Color, dark: Color) {
        switch kind {
        case .swift:
            return (hex(0xD47628), hex(0xFFA359))
        case .markdown:
            return (hex(0x199F43), hex(0x5ECC71))
        case .json:
            return (hex(0xD47628), hex(0xFFA359))
        case .yaml:
            return (hex(0xD52C36), hex(0xFF6762))
        case .shell:
            return (hex(0x199F43), hex(0x5ECC71))
        case .image:
            return (hex(0xD32A61), hex(0xFF678D))
        case .config, .uiResource:
            return (hex(0x84848A), hex(0xADADB1))
        case .generic:
            return (hex(0x84848A), hex(0xADADB1))
        }
    }

    private static func hex(_ value: UInt32) -> Color {
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }
}

struct FileTypeIconView: View {
    let path: String

    @Environment(\.colorScheme) private var colorScheme

    private var descriptor: FileTypeIconDescriptor {
        FileTypeIcon.resolve(for: path)
    }

    var body: some View {
        Image(systemName: descriptor.symbolName)
            .font(WorkbenchTypography.captionStrong)
            .foregroundStyle(descriptor.color(for: colorScheme))
            .frame(width: 14, alignment: .center)
            .accessibilityHidden(true)
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
