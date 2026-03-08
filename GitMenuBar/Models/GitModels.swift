import AppKit
import Foundation

struct Commit: Identifiable, Equatable {
    let id: String
    let shortHash: String
    let subject: String
    let body: String
    let authorName: String
    let authorEmail: String
    let committedAt: Date
    let stats: CommitStats
    let changedFiles: [CommitFileChange]
}

struct CommitStats: Equatable, Hashable {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}

struct CommitFileChange: Identifiable, Equatable, Hashable {
    let path: String
    let lineDiff: LineDiffStats

    var id: String {
        path
    }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directoryPath: String {
        let directory = (path as NSString).deletingLastPathComponent
        guard directory != ".", directory != path else {
            return ""
        }
        return directory
    }
}

struct LineDiffStats: Hashable {
    let added: Int
    let removed: Int

    static let zero = LineDiffStats(added: 0, removed: 0)
}

enum WorkingTreeFileStatus: String, Hashable {
    case modified
    case deleted
    case untracked

    var symbol: String {
        switch self {
        case .modified:
            return "M"
        case .deleted:
            return "D"
        case .untracked:
            return "U"
        }
    }

    var foregroundColor: NSColor {
        switch self {
        case .modified:
            return .systemBlue
        case .deleted:
            return .systemRed
        case .untracked:
            return .systemGreen
        }
    }

    var isDeleted: Bool {
        self == .deleted
    }
}

struct WorkingTreeFile: Identifiable, Hashable {
    let path: String
    let lineDiff: LineDiffStats
    let status: WorkingTreeFileStatus

    var id: String {
        path
    }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directoryPath: String {
        let directory = (path as NSString).deletingLastPathComponent
        guard directory != ".", directory != path else {
            return ""
        }
        return directory
    }
}

struct WorkingTreeSectionSummary: Equatable {
    let fileCount: Int
    let addedLineCount: Int
    let removedLineCount: Int

    var fileCountText: String {
        "\(fileCount)"
    }
}

extension Collection where Element == WorkingTreeFile {
    var sectionSummary: WorkingTreeSectionSummary {
        let addedLineCount = reduce(0) { partialResult, file in
            partialResult + file.lineDiff.added
        }
        let removedLineCount = reduce(0) { partialResult, file in
            partialResult + file.lineDiff.removed
        }

        return WorkingTreeSectionSummary(
            fileCount: count,
            addedLineCount: addedLineCount,
            removedLineCount: removedLineCount
        )
    }
}
