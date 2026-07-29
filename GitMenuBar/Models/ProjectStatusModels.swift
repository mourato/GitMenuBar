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
        if aheadCount > 0 && behindCount > 0 {
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

struct ProjectStatusReader {
    let runner: GitCommandRunner

    func read(project: ProjectReference, now: Date = Date()) -> ProjectStatusSnapshot {
        let root = runner.runGitCommand(in: project.path, args: ["rev-parse", "--show-toplevel"])
        guard !root.failure else {
            let exists = FileManager.default.fileExists(atPath: project.path)
            return ProjectStatusSnapshot(
                project: project, branchName: "", isDetachedHead: false, stagedCount: 0,
                unstagedCount: 0, untrackedCount: 0, aheadCount: 0, behindCount: 0,
                hasUpstream: false, lastRefreshedAt: nil,
                lastErrorDescription: exists ? "Not a Git repository" : "Folder unavailable"
            )
        }

        let status = runner.runGitCommand(in: project.path, args: ["status", "--porcelain", "-uall"])
        let counts = status.output.split(whereSeparator: \.isNewline).reduce(into: (0, 0, 0)) { result, line in
            guard line.count >= 2 else { return }
            let index = line[line.startIndex]
            let worktree = line[line.index(line.startIndex, offsetBy: 1)]
            if index != " " {
                result.0 += 1
            }
            if worktree == "?" {
                result.2 += 1
            } else if worktree != " " {
                result.1 += 1
            }
        }
        let branch = runner.runGitCommand(in: project.path, args: ["symbolic-ref", "--quiet", "--short", "HEAD"])
        let isDetached = branch.failure
        let branchName: String
        if isDetached {
            branchName = runner.runGitCommand(in: project.path, args: ["rev-parse", "--short", "HEAD"])
                .output.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            branchName = branch.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let upstream = runner.runGitCommand(in: project.path, args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        var ahead = 0
        var behind = 0
        if !upstream.failure {
            let counts = runner.runGitCommand(in: project.path, args: ["rev-list", "--left-right", "--count", "@{u}...HEAD"]).output
                .split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
            if counts.count == 2 {
                behind = counts[0]; ahead = counts[1]
            }
        }
        return ProjectStatusSnapshot(
            project: project, branchName: branchName, isDetachedHead: isDetached,
            stagedCount: counts.0, unstagedCount: counts.1, untrackedCount: counts.2,
            aheadCount: ahead, behindCount: behind, hasUpstream: !upstream.failure,
            lastRefreshedAt: now,
            lastErrorDescription: status.failure ? status.output : nil
        )
    }
}
