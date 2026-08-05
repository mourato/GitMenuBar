import Foundation

enum ProjectAttentionClassification: Equatable {
    case clean
    case needsAttention
    case unavailable
    case refreshing
}

enum ProjectAttentionReason: Equatable {
    case dirty
    case ahead
    case behind
    case diverged
    case noUpstream
    case detached
    case missing
    case invalidRepository
    case error
}

struct ProjectStatusSnapshot: Equatable, Identifiable {
    let project: ProjectReference
    let branchName: String
    let isDetachedHead: Bool
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let lineDiff: LineDiffStats
    let aheadCount: Int
    let behindCount: Int
    let hasUpstream: Bool
    let lastRefreshedAt: Date?
    let lastErrorDescription: String?

    var id: String {
        project.path
    }

    var hasWorkingTreeChanges: Bool {
        stagedCount + unstagedCount + untrackedCount > 0
    }

    var classification: ProjectAttentionClassification {
        if lastErrorDescription != nil {
            return .unavailable
        }
        if hasWorkingTreeChanges || aheadCount > 0 || behindCount > 0 || isDetachedHead || !hasUpstream {
            return .needsAttention
        }
        return .clean
    }

    var reasons: Set<ProjectAttentionReason> {
        var result = Set<ProjectAttentionReason>()
        if hasWorkingTreeChanges {
            result.insert(.dirty)
        }
        if aheadCount > 0, behindCount > 0 {
            result.insert(.diverged)
        } else if aheadCount > 0 {
            result.insert(.ahead)
        } else if behindCount > 0 {
            result.insert(.behind)
        }
        if !hasUpstream {
            result.insert(.noUpstream)
        }
        if isDetachedHead {
            result.insert(.detached)
        }
        if lastErrorDescription != nil {
            result.insert(.error)
        }
        return result
    }
}

enum ProjectStatusPorcelainParser {
    struct Result: Equatable {
        var branchName = ""
        var isDetachedHead = false
        var stagedCount = 0
        var unstagedCount = 0
        var untrackedCount = 0
        var untrackedPaths = Set<String>()
        var aheadCount = 0
        var behindCount = 0
        var hasUpstream = false

        var hasWorkingTreeChanges: Bool {
            stagedCount + unstagedCount + untrackedCount > 0
        }
    }

    static func parse(_ output: String) -> Result {
        var result = Result()
        var branchObjectID = ""

        for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
            if parseHeader(record, result: &result, branchObjectID: &branchObjectID) {
                continue
            }
            parseStatus(record, result: &result)
        }

        if result.isDetachedHead {
            result.branchName = String(branchObjectID.prefix(7))
        }
        return result
    }

    private static func parseHeader(
        _ record: Substring,
        result: inout Result,
        branchObjectID: inout String
    ) -> Bool {
        switch record {
        case let record where record.hasPrefix("# branch.head "):
            let value = String(record.dropFirst("# branch.head ".count))
            result.isDetachedHead = value == "(detached)"
            if !result.isDetachedHead {
                result.branchName = value
            }
        case let record where record.hasPrefix("# branch.oid "):
            branchObjectID = String(record.dropFirst("# branch.oid ".count))
        case let record where record.hasPrefix("# branch.upstream "):
            result.hasUpstream = !record.dropFirst("# branch.upstream ".count).isEmpty
        case let record where record.hasPrefix("# branch.ab "):
            let values = record.split(separator: " ")
            guard values.count == 4 else { return true }
            guard values[2].first == "+", values[3].first == "-",
                  let ahead = Int(values[2].dropFirst()),
                  let behind = Int(values[3].dropFirst()) else { return true }
            result.aheadCount = ahead
            result.behindCount = behind
        default:
            return false
        }
        return true
    }

    private static func parseStatus(_ record: Substring, result: inout Result) {
        if record.hasPrefix("? ") {
            result.untrackedCount += 1
            result.untrackedPaths.insert(String(record.dropFirst(2)))
            return
        }
        if record == "?" {
            result.untrackedCount += 1
            return
        }
        guard record.first == "1" || record.first == "2" || record.first == "u" else { return }
        let fields = record.split(separator: " ", maxSplits: 2)
        guard let status = fields.dropFirst().first, status.count == 2 else { return }
        let index = status[status.startIndex]
        let worktree = status[status.index(status.startIndex, offsetBy: 1)]
        if index != "." {
            result.stagedCount += 1
        }
        if worktree != "." {
            result.unstagedCount += 1
        }
    }
}

struct ProjectStatusReader {
    private static let emptyTreeHash = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    let runner: GitCommandRunner

    func read(project: ProjectReference, now: Date = Date()) -> ProjectStatusSnapshot {
        let status = runner.runGitCommand(
            in: project.path,
            args: ["status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"]
        )
        guard !status.failure else {
            let exists = FileManager.default.fileExists(atPath: project.path)
            let errorDescription: String = if !exists {
                "Folder unavailable"
            } else if status.output.localizedCaseInsensitiveContains("not a git repository") {
                "Not a Git repository"
            } else {
                status.output
            }
            return ProjectStatusSnapshot(
                project: project, branchName: "", isDetachedHead: false, stagedCount: 0,
                unstagedCount: 0, untrackedCount: 0, lineDiff: .zero, aheadCount: 0, behindCount: 0,
                hasUpstream: false, lastRefreshedAt: nil,
                lastErrorDescription: errorDescription
            )
        }

        let parsed = ProjectStatusPorcelainParser.parse(status.output)
        let lineDiff = parsed.hasWorkingTreeChanges
            ? readLineDiff(project: project, untrackedPaths: parsed.untrackedPaths)
            : .zero
        return ProjectStatusSnapshot(
            project: project, branchName: parsed.branchName, isDetachedHead: parsed.isDetachedHead,
            stagedCount: parsed.stagedCount, unstagedCount: parsed.unstagedCount, untrackedCount: parsed.untrackedCount,
            lineDiff: lineDiff,
            aheadCount: parsed.aheadCount, behindCount: parsed.behindCount, hasUpstream: parsed.hasUpstream,
            lastRefreshedAt: now,
            lastErrorDescription: nil
        )
    }

    private func readLineDiff(project: ProjectReference, untrackedPaths: Set<String>) -> LineDiffStats {
        let parser = WorkingTreeParser(runner: runner)
        let tracked = runner.runGitCommand(
            in: project.path,
            args: ["diff", "--numstat", "--no-renames", "HEAD", "--"]
        )
        let trackedStats: LineDiffStats
        if tracked.failure {
            let emptyTree = runner.runGitCommand(
                in: project.path,
                args: ["diff", "--numstat", "--no-renames", Self.emptyTreeHash, "--"]
            )
            trackedStats = emptyTree.failure
                ? .zero
                : parser.parseNumstat(emptyTree.output).values.reduce(into: .zero) { total, stats in
                    total = LineDiffStats(
                        added: total.added + stats.added,
                        removed: total.removed + stats.removed
                    )
                }
        } else {
            trackedStats = parser.parseNumstat(tracked.output).values.reduce(into: .zero) { total, stats in
                total = LineDiffStats(
                    added: total.added + stats.added,
                    removed: total.removed + stats.removed
                )
            }
        }

        let untrackedStats = parser.lineDiffForUntrackedFiles(
            paths: untrackedPaths,
            repositoryPath: project.path
        ).values.reduce(into: .zero) { total, stats in
            total = LineDiffStats(
                added: total.added + stats.added,
                removed: total.removed + stats.removed
            )
        }

        return LineDiffStats(
            added: trackedStats.added + untrackedStats.added,
            removed: trackedStats.removed + untrackedStats.removed
        )
    }
}
