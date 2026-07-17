//
//  WorktreeParser.swift
//  GitMenuBar
//

import Foundation

struct WorktreeParser {
    private enum ParsedLine {
        case path(String)
        case head(String)
        case branch(String)
        case locked(String)
        case prunable(String)
        case ignored
    }

    func parse(_ output: String) throws -> [GitWorktreeInfo] {
        let normalizedOutput = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let records = normalizedOutput
            .components(separatedBy: "\n\n")
            .map { record in
                record
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .newlines) }
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }

        return try records.enumerated().map { index, lines in
            try parseRecord(lines, recordIndex: index)
        }
    }

    private func parseRecord(
        _ lines: [String],
        recordIndex: Int
    ) throws -> GitWorktreeInfo {
        var path: String?
        var headHash: String?
        var branchName: String?
        var lockReason: String?
        var pruneReason: String?

        for line in lines {
            switch parseLine(line) {
            case let .path(value):
                path = value
            case let .head(value):
                headHash = value
            case let .branch(value):
                branchName = value
            case let .locked(value):
                lockReason = value
            case let .prunable(value):
                pruneReason = value
            case .ignored:
                break
            }
        }

        guard let path, !path.isEmpty else {
            throw GitWorktreeParserError.missingPath(recordIndex: recordIndex)
        }
        guard let headHash, !headHash.isEmpty else {
            throw GitWorktreeParserError.missingHead(recordIndex: recordIndex)
        }

        return GitWorktreeInfo(
            path: path,
            headHash: headHash,
            branchName: branchName,
            isMainWorktree: recordIndex == 0,
            lockReason: lockReason,
            pruneReason: pruneReason
        )
    }

    private func parseLine(_ line: String) -> ParsedLine {
        switch line {
        case let line where line.hasPrefix("worktree "):
            return .path(String(line.dropFirst("worktree ".count)))
        case let line where line.hasPrefix("HEAD "):
            return .head(String(line.dropFirst("HEAD ".count)))
        case let line where line.hasPrefix("branch "):
            let ref = String(line.dropFirst("branch ".count))
            guard ref.hasPrefix("refs/heads/") else {
                return .ignored
            }
            return .branch(String(ref.dropFirst("refs/heads/".count)))
        case "locked":
            return .locked("")
        case let line where line.hasPrefix("locked "):
            return .locked(String(line.dropFirst("locked ".count)))
        case "prunable":
            return .prunable("")
        case let line where line.hasPrefix("prunable "):
            return .prunable(String(line.dropFirst("prunable ".count)))
        default:
            return .ignored
        }
    }
}
