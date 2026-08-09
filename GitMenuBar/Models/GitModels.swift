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
            "M"
        case .deleted:
            "D"
        case .untracked:
            "U"
        }
    }

    var foregroundColor: NSColor {
        switch self {
        case .modified:
            .systemBlue
        case .deleted:
            .systemRed
        case .untracked:
            .systemGreen
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

extension Collection<WorkingTreeFile> {
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
            "Up to date"
        case let .ahead(count):
            "Ahead by \(count)"
        case let .behind(count):
            "Behind by \(count)"
        case let .diverged(ahead, behind):
            "Diverged: ahead \(ahead), behind \(behind)"
        case .noRemote:
            "No upstream"
        case .unknown:
            "Unknown"
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

enum GitWorktreeWorkingTreeState: Hashable {
    case clean
    case dirty
    case unknown
}

struct GitWorktreeInfo: Identifiable, Hashable {
    let path: String
    let headHash: String
    let branchName: String?
    let isMainWorktree: Bool
    let lockReason: String?
    let pruneReason: String?
    let workingTreeState: GitWorktreeWorkingTreeState

    init(
        path: String,
        headHash: String,
        branchName: String?,
        isMainWorktree: Bool = false,
        lockReason: String? = nil,
        pruneReason: String? = nil,
        workingTreeState: GitWorktreeWorkingTreeState = .unknown
    ) {
        self.path = path
        self.headHash = headHash
        self.branchName = branchName
        self.isMainWorktree = isMainWorktree
        self.lockReason = lockReason
        self.pruneReason = pruneReason
        self.workingTreeState = workingTreeState
    }

    var id: String {
        path
    }

    var isDetached: Bool {
        branchName == nil
    }
}

enum GitWorktreeParserError: LocalizedError, Equatable {
    case missingPath(recordIndex: Int)
    case missingHead(recordIndex: Int)

    var errorDescription: String? {
        switch self {
        case let .missingPath(recordIndex):
            "Worktree record \(recordIndex + 1) is missing its path."
        case let .missingHead(recordIndex):
            "Worktree record \(recordIndex + 1) is missing its HEAD."
        }
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
    var hunks: [String]
    var message: String

    init(id: UUID = UUID(), files: [String], hunks: [String] = [], message: String) {
        self.id = id
        self.files = files
        self.hunks = hunks
        self.message = message
    }

    var fileCount: Int {
        files.count
    }

    var selectionCount: Int {
        files.count + hunks.count
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
    case duplicateHunk(String)
    case unknownHunk(String)
    case fileHunkOverlap(String)

    var errorDescription: String? {
        switch self {
        case .emptyPlan:
            "No atomic commit groups to commit."
        case let .emptyGroup(index):
            "Atomic commit group \(index + 1) has no files."
        case let .emptyMessage(index):
            "Atomic commit group \(index + 1) has an empty commit message."
        case let .duplicateFile(file):
            "File '\(file)' appears in more than one atomic commit group."
        case let .unknownFile(file):
            "File '\(file)' is not part of the current working tree changes."
        case let .duplicateHunk(hunk):
            "Hunk '\(hunk)' appears in more than one atomic commit group."
        case let .unknownHunk(hunk):
            "Hunk '\(hunk)' is not part of the current working tree changes."
        case let .fileHunkOverlap(file):
            "File '\(file)' cannot be committed as a whole and by hunk."
        }
    }
}

struct AtomicCommitPlan: Equatable {
    let groups: [AtomicCommitGroup]

    private struct ValidationState {
        var seenFiles = Set<String>()
        var seenHunks = Set<String>()
        var wholeFiles = Set<String>()
        var hunkPaths = Set<String>()
    }

    init(groups: [AtomicCommitGroup], allowedFiles: Set<String>) throws {
        try self.init(groups: groups, allowedFiles: allowedFiles, hunksByID: [:])
    }

    init(
        groups: [AtomicCommitGroup],
        allowedFiles: Set<String>,
        hunksByID: [String: AtomicCommitHunk]
    ) throws {
        guard !groups.isEmpty else {
            throw AtomicCommitPlanValidationError.emptyPlan
        }

        var state = ValidationState()
        let validatedGroups = try groups.enumerated().map { index, group in
            try Self.validateGroup(
                group,
                index: index,
                allowedFiles: allowedFiles,
                hunksByID: hunksByID,
                state: &state
            )
        }
        if let overlap = state.wholeFiles.intersection(state.hunkPaths).first {
            throw AtomicCommitPlanValidationError.fileHunkOverlap(overlap)
        }
        self.groups = validatedGroups
    }

    private static func validateGroup(
        _ group: AtomicCommitGroup,
        index: Int,
        allowedFiles: Set<String>,
        hunksByID: [String: AtomicCommitHunk],
        state: inout ValidationState
    ) throws -> AtomicCommitGroup {
        let files = group.files
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hunks = group.hunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !files.isEmpty || !hunks.isEmpty else {
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
            guard state.seenFiles.insert(file).inserted else {
                throw AtomicCommitPlanValidationError.duplicateFile(file)
            }
            state.wholeFiles.insert(file)
        }

        for hunk in hunks {
            guard let metadata = hunksByID[hunk] else {
                throw AtomicCommitPlanValidationError.unknownHunk(hunk)
            }
            guard allowedFiles.contains(metadata.path) else {
                throw AtomicCommitPlanValidationError.unknownFile(metadata.path)
            }
            guard state.seenHunks.insert(hunk).inserted else {
                throw AtomicCommitPlanValidationError.duplicateHunk(hunk)
            }
            state.hunkPaths.insert(metadata.path)
        }

        return AtomicCommitGroup(id: group.id, files: files, hunks: hunks, message: message)
    }
}

struct AtomicCommitHunk: Equatable, Hashable, Identifiable {
    let id: String
    let path: String
    let ordinal: Int
    let header: String
    let additions: Int
    let removals: Int
    let patch: String
}

struct AtomicCommitSnapshot: Equatable {
    let head: String
    let fingerprint: String
    let files: [WorkingTreeFile]
    let hunks: [AtomicCommitHunk]

    init(
        head: String = "",
        fingerprint: String,
        files: [WorkingTreeFile],
        hunks: [AtomicCommitHunk]
    ) {
        self.head = head
        self.fingerprint = fingerprint
        self.files = files
        self.hunks = hunks
    }

    var filesByPath: [String: WorkingTreeFile] {
        Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
    }

    var hunksByID: [String: AtomicCommitHunk] {
        Dictionary(uniqueKeysWithValues: hunks.map { ($0.id, $0) })
    }

    var allowedFiles: Set<String> {
        Set(files.map(\.path))
    }

    static func fallback(for files: [WorkingTreeFile], fingerprint: String = "") -> AtomicCommitSnapshot {
        AtomicCommitSnapshot(fingerprint: fingerprint, files: files, hunks: [])
    }
}

struct AtomicCommitExecutionPlan: Equatable {
    let groups: [AtomicCommitGroup]
    let snapshot: AtomicCommitSnapshot
}
