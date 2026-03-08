import Foundation

enum PathDisplayFormatter {
    static func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func projectName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    static func recentProjectLabel(for path: String, showFullPath: Bool) -> String {
        showFullPath ? abbreviatedPath(path) : projectName(from: path)
    }
}
