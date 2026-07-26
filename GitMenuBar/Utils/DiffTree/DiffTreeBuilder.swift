import Foundation

enum DiffTreeBuilder {
    private final class MutableDirectoryNode {
        let name: String
        let path: String
        var stat: DiffTreeStat
        var directories: [String: MutableDirectoryNode] = [:]
        var files: [DiffTreeNode] = []

        init(name: String, path: String, stat: DiffTreeStat) {
            self.name = name
            self.path = path
            self.stat = stat
        }
    }

    static func summarizeDiffTreeStats(_ inputs: some Sequence<DiffTreeFileInput>) -> DiffTreeStat {
        inputs.reduce(into: DiffTreeStat.zero) { totals, input in
            guard let stat = input.stat else {
                return
            }
            totals = DiffTreeStat(
                additions: totals.additions + stat.additions,
                deletions: totals.deletions + stat.deletions
            )
        }
    }

    static func buildDiffTree(_ inputs: some Sequence<DiffTreeFileInput>) -> [DiffTreeNode] {
        let root = MutableDirectoryNode(name: "", path: "", stat: .zero)

        for input in inputs {
            let segments = normalizePathSegments(input.path)
            guard !segments.isEmpty, let fileName = segments.last else {
                continue
            }

            let filePath = segments.joined(separator: "/")
            var ancestors: [MutableDirectoryNode] = [root]
            var currentDirectory = root

            for segment in segments.dropLast() {
                let nextPath = currentDirectory.path.isEmpty
                    ? segment
                    : "\(currentDirectory.path)/\(segment)"

                if let existing = currentDirectory.directories[segment] {
                    currentDirectory = existing
                } else {
                    let created = MutableDirectoryNode(name: segment, path: nextPath, stat: .zero)
                    currentDirectory.directories[segment] = created
                    currentDirectory = created
                }
                ancestors.append(currentDirectory)
            }

            currentDirectory.files.append(
                .file(name: fileName, path: filePath, stat: input.stat)
            )

            if let stat = input.stat {
                for ancestor in ancestors {
                    ancestor.stat = DiffTreeStat(
                        additions: ancestor.stat.additions + stat.additions,
                        deletions: ancestor.stat.deletions + stat.deletions
                    )
                }
            }
        }

        return toTreeNodes(root)
    }

    private static func normalizePathSegments(_ pathValue: String) -> [String] {
        pathValue
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func compareByName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func toTreeNodes(_ directory: MutableDirectoryNode) -> [DiffTreeNode] {
        let subdirectories = directory.directories.values
            .sorted { compareByName($0.name, $1.name) }
            .map { subdirectory -> DiffTreeNode in
                compactDirectoryNode(
                    .directory(
                        name: subdirectory.name,
                        path: subdirectory.path,
                        stat: subdirectory.stat,
                        children: toTreeNodes(subdirectory)
                    )
                )
            }

        let files = directory.files.sorted { lhs, rhs in
            compareByName(nodeName(lhs), nodeName(rhs))
        }

        return subdirectories + files
    }

    private static func compactDirectoryNode(_ node: DiffTreeNode) -> DiffTreeNode {
        guard case let .directory(name, path, stat, children) = node else {
            return node
        }

        let compactedChildren = children.map { child in
            switch child {
            case .directory:
                return compactDirectoryNode(child)
            case .file:
                return child
            }
        }

        var compactedName = name
        var compactedPath = path
        var compactedStat = stat
        var compactedChildNodes = compactedChildren

        while compactedChildNodes.count == 1 {
            guard case let .directory(onlyChildName, onlyChildPath, onlyChildStat, onlyChildChildren) =
                compactedChildNodes[0] else {
                break
            }
            compactedName = "\(compactedName)/\(onlyChildName)"
            compactedPath = onlyChildPath
            compactedStat = onlyChildStat
            compactedChildNodes = onlyChildChildren
        }

        return .directory(
            name: compactedName,
            path: compactedPath,
            stat: compactedStat,
            children: compactedChildNodes
        )
    }

    private static func nodeName(_ node: DiffTreeNode) -> String {
        switch node {
        case let .directory(name, _, _, _):
            return name
        case let .file(name, _, _):
            return name
        }
    }
}
