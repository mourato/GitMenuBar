import Foundation

enum FileTypeSymbol {
    static func fileIconName(for path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        let fileExtension = (fileName as NSString).pathExtension.lowercased()

        switch fileExtension {
        case "swift":
            return "swift"
        case "md", "markdown":
            return "doc.richtext"
        case "json", "yaml", "yml":
            return "curlybraces"
        case "plist", "xcconfig", "entitlements":
            return "doc.badge.gearshape"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "pdf":
            return "photo"
        case "sh", "bash", "zsh":
            return "terminal"
        case "xcassets", "storyboard", "xib":
            return "square.grid.2x2"
        default:
            if fileName.hasPrefix("Makefile") || fileName == "Dockerfile" {
                return "doc.badge.gearshape"
            }
            return "doc"
        }
    }

    static func directoryIconName(isExpanded: Bool) -> String {
        isExpanded ? "folder.fill" : "folder"
    }
}
