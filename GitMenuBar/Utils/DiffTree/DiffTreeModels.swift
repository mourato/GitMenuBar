import Foundation

struct DiffTreeStat: Equatable, Hashable {
    let additions: Int
    let deletions: Int

    static let zero = DiffTreeStat(additions: 0, deletions: 0)
}

enum DiffTreeNode: Equatable, Hashable {
    case directory(name: String, path: String, stat: DiffTreeStat, children: [DiffTreeNode])
    case file(name: String, path: String, stat: DiffTreeStat?)
}

struct DiffTreeFileInput: Equatable, Hashable {
    let path: String
    let stat: DiffTreeStat?
}

extension LineDiffStats {
    var diffTreeStat: DiffTreeStat {
        DiffTreeStat(additions: added, deletions: removed)
    }
}

extension CommitFileChange {
    var diffTreeFileInput: DiffTreeFileInput {
        DiffTreeFileInput(path: path, stat: lineDiff.diffTreeStat)
    }
}
