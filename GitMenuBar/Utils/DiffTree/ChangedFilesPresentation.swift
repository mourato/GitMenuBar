import Foundation

enum ChangedFilesPresentation {
    static let autoExpandFileLimit = 5
    static let autoExpandLineLimit = 200
    static let previewFileLimit = 3
    static let previewScopeLimit = 4

    static func shouldAutoExpandChangedFiles(
        fileCount: Int,
        totalChangedLines: Int,
        isPrimaryContext: Bool
    ) -> Bool {
        guard isPrimaryContext else {
            return false
        }
        guard fileCount <= autoExpandFileLimit else {
            return false
        }
        return totalChangedLines <= autoExpandLineLimit
    }

    static func changedFileName(path: String) -> String {
        let segments = pathSegments(path)
        return segments.last ?? path
    }

    static func summarizeChangedFileScopes(
        paths: [String],
        limit: Int = previewScopeLimit
    ) -> [ChangedFilesScopeSummary] {
        var scopes: [String: (fileCount: Int, firstIndex: Int)] = [:]

        for (index, path) in paths.enumerated() {
            let label = changedFileScope(path)
            if let current = scopes[label] {
                scopes[label] = (fileCount: current.fileCount + 1, firstIndex: current.firstIndex)
            } else {
                scopes[label] = (fileCount: 1, firstIndex: index)
            }
        }

        return scopes
            .map { label, scope in
                (label: label, fileCount: scope.fileCount, firstIndex: scope.firstIndex)
            }
            .sorted { lhs, rhs in
                if lhs.fileCount != rhs.fileCount {
                    return lhs.fileCount > rhs.fileCount
                }
                if lhs.firstIndex != rhs.firstIndex {
                    return lhs.firstIndex < rhs.firstIndex
                }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
            .prefix(limit)
            .map { ChangedFilesScopeSummary(label: $0.label, fileCount: $0.fileCount) }
    }

    static func selectChangedFilePreview(
        paths: [String],
        limit: Int = previewFileLimit
    ) -> [String] {
        var selected: [String] = []
        var selectedPaths = Set<String>()
        var selectedScopes = Set<String>()

        for path in paths {
            let scope = changedFileScope(path)
            guard !selectedScopes.contains(scope) else {
                continue
            }
            selected.append(path)
            selectedPaths.insert(path)
            selectedScopes.insert(scope)
            if selected.count == limit {
                return selected
            }
        }

        for path in paths where !selectedPaths.contains(path) {
            selected.append(path)
            if selected.count == limit {
                break
            }
        }

        return selected
    }

    private static func pathSegments(_ pathValue: String) -> [String] {
        pathValue
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func changedFileScope(_ pathValue: String) -> String {
        let segments = pathSegments(pathValue)
        return segments.count > 1 ? segments[0] : "root"
    }
}

struct ChangedFilesScopeSummary: Equatable, Hashable {
    let label: String
    let fileCount: Int
}
