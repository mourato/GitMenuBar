import Foundation

enum FileTypeSymbol {
    static func fileIconName(for path: String) -> String {
        FileTypeIcon.resolve(for: path).symbolName
    }

    static func directoryIconName(isExpanded: Bool) -> String {
        FileTypeIcon.directoryIconName(isExpanded: isExpanded)
    }
}
