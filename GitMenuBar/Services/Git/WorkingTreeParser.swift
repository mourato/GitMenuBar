import Foundation

final class WorkingTreeParser {
    struct PorcelainStatus {
        let stagedStatuses: [String: WorkingTreeFileStatus]
        let changedStatuses: [String: WorkingTreeFileStatus]
        let untrackedPaths: Set<String>
    }

    init(runner _: GitCommandRunner) {}

    func parsePorcelainStatus(_ output: String) -> PorcelainStatus {
        var stagedStatuses: [String: WorkingTreeFileStatus] = [:]
        var changedStatuses: [String: WorkingTreeFileStatus] = [:]
        var untrackedPaths = Set<String>()

        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            guard line.count >= 3, let path = parsePathFromStatusLine(line) else {
                continue
            }

            let indexStatus = line[line.startIndex]
            let worktreeStatus = line[line.index(after: line.startIndex)]

            if indexStatus == "!", worktreeStatus == "!" {
                continue
            }

            if indexStatus == "?", worktreeStatus == "?" {
                untrackedPaths.insert(path)
                changedStatuses[path] = .untracked
                continue
            }

            if indexStatus != " " {
                stagedStatuses[path] = visualStatus(for: indexStatus)
            }

            if worktreeStatus != " " {
                changedStatuses[path] = visualStatus(for: worktreeStatus)
            }
        }

        return PorcelainStatus(
            stagedStatuses: stagedStatuses,
            changedStatuses: changedStatuses,
            untrackedPaths: untrackedPaths
        )
    }

    func parseNumstat(_ output: String) -> [String: LineDiffStats] {
        var map: [String: LineDiffStats] = [:]

        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }

            let addedRaw = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let removedRaw = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let path = parts.dropFirst(2).joined(separator: "\t").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }

            let added = Int(addedRaw) ?? 0
            let removed = Int(removedRaw) ?? 0
            map[path] = LineDiffStats(added: added, removed: removed)
        }

        return map
    }

    func lineDiffForUntrackedFiles(
        paths: Set<String>,
        repositoryPath: String
    ) -> [String: LineDiffStats] {
        paths.reduce(into: [:]) { result, path in
            result[path] = LineDiffStats(added: lineCountForFile(path, repositoryPath: repositoryPath), removed: 0)
        }
    }

    private func visualStatus(for statusCode: Character) -> WorkingTreeFileStatus {
        switch statusCode {
        case "?", "A":
            return .untracked
        case "D":
            return .deleted
        default:
            return .modified
        }
    }

    private func parsePathFromStatusLine(_ line: String) -> String? {
        guard line.count >= 3 else { return nil }
        var path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        if let arrowRange = path.range(of: " -> ") {
            path = String(path[arrowRange.upperBound...])
        }

        if path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 {
            path = String(path.dropFirst().dropLast())
        }

        return path.isEmpty ? nil : path
    }

    private func lineCountForFile(_ path: String, repositoryPath: String) -> Int {
        let repositoryURL = URL(fileURLWithPath: repositoryPath).standardizedFileURL
        let fullURL = repositoryURL.appendingPathComponent(path).standardizedFileURL
        guard fullURL.path == repositoryURL.path || fullURL.path.hasPrefix(repositoryURL.path + "/") else {
            return 0
        }

        let fullPath = fullURL.path
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8), !content.isEmpty else {
            return 0
        }

        let components = content.components(separatedBy: "\n")
        if content.hasSuffix("\n") {
            return max(components.count - 1, 0)
        }
        return components.count
    }
}
