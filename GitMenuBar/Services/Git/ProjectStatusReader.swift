import Foundation

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

enum ProjectStatusReadMode {
    case local(pullRequests: [GitHubPullRequestSummary], branchHealth: ProjectStatusReader.BranchHealth)
    case remote

    /// Values captured from the last known snapshot that a local read carries
    /// forward instead of re-reading branch health and pull requests.
    var localRead: (pullRequests: [GitHubPullRequestSummary], branchHealth: ProjectStatusReader.BranchHealth)? {
        if case let .local(pullRequests, branchHealth) = self {
            return (pullRequests, branchHealth)
        }
        return nil
    }
}

struct ProjectStatusReader {
    private static let emptyTreeHash = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    let runner: GitCommandRunner

    struct BranchHealth: Equatable {
        var branchesWithoutUpstreamCount = 0
        var unpushedBranchCount = 0
        var unmergedBranchCount = 0
        var stashCount = 0
        var lastActivityAt: Date?
    }

    struct BranchTrackingHealth: Equatable {
        var branchesWithoutUpstreamCount = 0
        var unpushedBranchCount = 0
        var lastActivityAt: Date?
    }

    static func parseBranchTracking(_ output: String, currentBranch: String? = nil) -> BranchTrackingHealth {
        var withoutUpstream = 0
        var unpushed = 0
        var latestCommitTimestamp: Int?
        var currentCommitTimestamp: Int?

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            if fields[1].isEmpty {
                withoutUpstream += 1
            } else if fields[2].contains("ahead") {
                unpushed += 1
            }
            if fields.count >= 4, let timestamp = Int(fields[3]) {
                latestCommitTimestamp = max(latestCommitTimestamp ?? timestamp, timestamp)
                if let currentBranch, String(fields[0]) == currentBranch {
                    currentCommitTimestamp = timestamp
                }
            }
        }

        return BranchTrackingHealth(
            branchesWithoutUpstreamCount: withoutUpstream,
            unpushedBranchCount: unpushed,
            lastActivityAt: (currentCommitTimestamp ?? latestCommitTimestamp).map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
        )
    }

    static func countBranchLines(_ output: String) -> Int {
        output.split(whereSeparator: \.isNewline)
            .filter { !String($0).trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    func read(
        project: ProjectReference,
        now: Date = Date(),
        includeLineDiff: Bool = true,
        mode: ProjectStatusReadMode = .remote
    ) -> ProjectStatusSnapshot {
        let status = runner.runGitCommand(
            in: project.path,
            args: ["status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"]
        )
        let lastKnown = mode.localRead
        guard !status.failure else {
            let exists = FileManager.default.fileExists(atPath: project.path)
            let errorDescription: String = if !exists {
                "Folder unavailable"
            } else if status.output.localizedStandardContains("not a git repository") {
                "Not a Git repository"
            } else {
                status.output
            }
            return ProjectStatusSnapshot(
                project: project, branchName: "", isDetachedHead: false, stagedCount: 0,
                unstagedCount: 0, untrackedCount: 0, lineDiff: .zero, aheadCount: 0, behindCount: 0,
                hasUpstream: false, lastRefreshedAt: nil,
                lastErrorDescription: errorDescription,
                branchesWithoutUpstreamCount: lastKnown?.branchHealth.branchesWithoutUpstreamCount ?? 0,
                unpushedBranchCount: lastKnown?.branchHealth.unpushedBranchCount ?? 0,
                unmergedBranchCount: lastKnown?.branchHealth.unmergedBranchCount ?? 0,
                stashCount: lastKnown?.branchHealth.stashCount ?? 0,
                lastActivityAt: lastKnown?.branchHealth.lastActivityAt,
                pullRequests: lastKnown?.pullRequests ?? []
            )
        }

        let parsed = ProjectStatusPorcelainParser.parse(status.output)
        // Local reads carry the last known snapshot data through the mode, so
        // branch health and pull requests are not re-read on file events.
        let branchHealth = lastKnown?.branchHealth
            ?? readBranchHealth(projectPath: project.path, currentBranch: parsed.branchName)
        let pullRequests = lastKnown?.pullRequests
            ?? GitHubPullRequestStatusReader(runner: runner).read(projectPath: project.path)
        let lineDiff = includeLineDiff && parsed.hasWorkingTreeChanges
            ? readLineDiff(project: project, untrackedPaths: parsed.untrackedPaths)
            : .zero
        return ProjectStatusSnapshot(
            project: project, branchName: parsed.branchName, isDetachedHead: parsed.isDetachedHead,
            stagedCount: parsed.stagedCount, unstagedCount: parsed.unstagedCount, untrackedCount: parsed.untrackedCount,
            lineDiff: lineDiff,
            aheadCount: parsed.aheadCount, behindCount: parsed.behindCount, hasUpstream: parsed.hasUpstream,
            lastRefreshedAt: now,
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: branchHealth.branchesWithoutUpstreamCount,
            unpushedBranchCount: branchHealth.unpushedBranchCount,
            unmergedBranchCount: branchHealth.unmergedBranchCount,
            stashCount: branchHealth.stashCount,
            lastActivityAt: branchHealth.lastActivityAt,
            pullRequests: pullRequests
        )
    }

    private func readBranchHealth(projectPath: String, currentBranch: String) -> BranchHealth {
        let repository = GitCleanupRepository(runner: runner)
        let unmerged = repository.localBranchesNotIntegrated(
            in: projectPath,
            defaultBranchName: repository.resolvedDefaultBranchName(in: projectPath)
        )
        let tracking = runner.runGitCommand(
            in: projectPath,
            args: [
                "for-each-ref",
                "--format=%(refname:short)%00%(upstream:short)%00%(upstream:track,nobracket)%00%(committerdate:unix)",
                "refs/heads"
            ]
        )
        let stashes = runner.runGitCommand(in: projectPath, args: ["stash", "list", "--format=%H"])
        let trackingCounts = Self.parseBranchTracking(tracking.output, currentBranch: currentBranch)
        return BranchHealth(
            branchesWithoutUpstreamCount: tracking.failure ? 0 : trackingCounts.branchesWithoutUpstreamCount,
            unpushedBranchCount: tracking.failure ? 0 : trackingCounts.unpushedBranchCount,
            unmergedBranchCount: unmerged?.count ?? 0,
            stashCount: stashes.failure ? 0 : Self.countBranchLines(stashes.output),
            lastActivityAt: tracking.failure ? nil : trackingCounts.lastActivityAt
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
