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
    let isMergeCommit: Bool
    let stats: CommitStats
    let changedFiles: [CommitFileChange]

    init(
        id: String,
        shortHash: String,
        subject: String,
        body: String,
        authorName: String,
        authorEmail: String,
        committedAt: Date,
        isMergeCommit: Bool = false,
        stats: CommitStats,
        changedFiles: [CommitFileChange]
    ) {
        self.id = id
        self.shortHash = shortHash
        self.subject = subject
        self.body = body
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.committedAt = committedAt
        self.isMergeCommit = isMergeCommit
        self.stats = stats
        self.changedFiles = changedFiles
    }
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

enum BranchTrackingStatus: Hashable {
    case upToDate
    case ahead(Int)
    case behind(Int)
    case diverged(ahead: Int, behind: Int)
    case noRemote
    case unknown
}

extension BranchTrackingStatus {
    var description: String {
        switch self {
        case .upToDate:
            return "Up to date"
        case let .ahead(count):
            return "Ahead by \(count)"
        case let .behind(count):
            return "Behind by \(count)"
        case let .diverged(ahead, behind):
            return "Diverged: ahead \(ahead), behind \(behind)"
        case .noRemote:
            return "No upstream"
        case .unknown:
            return "Unknown"
        }
    }
}

struct BranchInfo: Identifiable, Hashable {
    let name: String
    let isLocal: Bool
    let isRemote: Bool
    let isCurrent: Bool
    let trackingStatus: BranchTrackingStatus
    let lastCommitDate: Date?

    var id: String {
        "\(isLocal ? "local" : "remote")/\(name)"
    }

    var displayName: String {
        isRemote ? "origin/\(name)" : name
    }
}

struct MergeToDefaultResult: Equatable {
    let didSwitchToDefault: Bool
    let didMerge: Bool
    let didDeleteLocal: Bool
    let didDeleteRemote: Bool
    let defaultBranchName: String
    let featureBranchName: String
}

enum BranchCleanupOption: String, CaseIterable {
    case deleteLocal = "Delete Local Only"
    case deleteLocalAndRemote = "Delete Local & Remote"
    case deleteRemoteOnly = "Delete Remote Only"
    case keep = "Keep Branch"
}

struct AtomicCommitGroup: Identifiable, Equatable, Hashable {
    let id: UUID
    var files: [String]
    var message: String

    init(id: UUID = UUID(), files: [String], message: String) {
        self.id = id
        self.files = files
        self.message = message
    }

    var fileCount: Int {
        files.count
    }

    /// One-commit-per-file fallback used when grouping is unavailable.
    static func fallbackGroups(for files: [WorkingTreeFile]) -> [AtomicCommitGroup] {
        files.map { AtomicCommitGroup(files: [$0.path], message: "chore: update \($0.fileName)") }
    }
}

enum AtomicCommitPlanValidationError: LocalizedError, Equatable {
    case emptyPlan
    case emptyGroup(Int)
    case emptyMessage(Int)
    case duplicateFile(String)
    case unknownFile(String)

    var errorDescription: String? {
        switch self {
        case .emptyPlan:
            return "No atomic commit groups to commit."
        case let .emptyGroup(index):
            return "Atomic commit group \(index + 1) has no files."
        case let .emptyMessage(index):
            return "Atomic commit group \(index + 1) has an empty commit message."
        case let .duplicateFile(file):
            return "File '\(file)' appears in more than one atomic commit group."
        case let .unknownFile(file):
            return "File '\(file)' is not part of the current working tree changes."
        }
    }
}

struct AtomicCommitPlan: Equatable {
    let groups: [AtomicCommitGroup]

    init(groups: [AtomicCommitGroup], allowedFiles: Set<String>) throws {
        guard !groups.isEmpty else {
            throw AtomicCommitPlanValidationError.emptyPlan
        }

        var seenFiles = Set<String>()
        var validatedGroups: [AtomicCommitGroup] = []

        for (index, group) in groups.enumerated() {
            let files = group.files
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !files.isEmpty else {
                throw AtomicCommitPlanValidationError.emptyGroup(index)
            }

            let message = group.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                throw AtomicCommitPlanValidationError.emptyMessage(index)
            }

            for file in files {
                guard allowedFiles.contains(file) else {
                    throw AtomicCommitPlanValidationError.unknownFile(file)
                }
                guard seenFiles.insert(file).inserted else {
                    throw AtomicCommitPlanValidationError.duplicateFile(file)
                }
            }

            validatedGroups.append(AtomicCommitGroup(id: group.id, files: files, message: message))
        }

        self.groups = validatedGroups
    }
}
