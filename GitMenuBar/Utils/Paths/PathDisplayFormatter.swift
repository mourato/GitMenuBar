import Foundation

enum PathDisplayFormatter {
    static func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func defaultProjectName(for path: String) -> String {
        let expandedPath = expandedPath(path)
        let lastPathComponent = URL(fileURLWithPath: expandedPath).lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }

        let fallbackName = (expandedPath as NSString).lastPathComponent
        return fallbackName.isEmpty ? path : fallbackName
    }

    static func projectName(from path: String) -> String {
        defaultProjectName(for: path)
    }

    static func recentProjectLabel(for path: String, showFullPath: Bool) -> String {
        showFullPath ? abbreviatedPath(path) : projectName(from: path)
    }
}
