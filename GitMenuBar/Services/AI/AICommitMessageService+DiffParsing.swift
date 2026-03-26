import Foundation

extension AICommitMessageService {
    private static let diffHeaderRegex = try? NSRegularExpression(
        pattern: #"^diff --git (?:"a/(.+)"|a/(\S+)) (?:"b/(.+)"|b/(\S+))$"#
    )

    func parseSections(from diff: String) -> [ParsedDiffSection] {
        let lines = diff.components(separatedBy: .newlines)
        var sections: [[String]] = []
        var current: [String] = []

        for line in lines {
            if line.hasPrefix("diff --git "), !current.isEmpty {
                sections.append(current)
                current = [line]
                continue
            }

            current.append(line)
        }

        if !current.isEmpty {
            sections.append(current)
        }

        return sections.compactMap { rawSection in
            let content = rawSection.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                return nil
            }

            let header = rawSection.first ?? ""
            let path = parsePath(fromDiffHeader: header) ?? "working-tree"
            return ParsedDiffSection(
                path: path,
                content: content,
                lineDiff: lineDiff(for: content)
            )
        }
    }

    func parsePath(fromDiffHeader header: String) -> String? {
        guard header.hasPrefix("diff --git "), let regex = Self.diffHeaderRegex else {
            return nil
        }

        let fullRange = NSRange(header.startIndex ..< header.endIndex, in: header)
        guard let match = regex.firstMatch(in: header, options: [], range: fullRange) else {
            return nil
        }

        let candidates = [3, 4, 1, 2]
        for group in candidates {
            let range = match.range(at: group)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: header) else {
                continue
            }

            let value = String(header[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }

    func lineDiff(for section: String) -> LineDiffStats {
        var added = 0
        var removed = 0

        for line in section.components(separatedBy: .newlines) {
            if line.hasPrefix("+++ ") || line.hasPrefix("--- ") {
                continue
            }

            if line.hasPrefix("+") {
                added += 1
                continue
            }

            if line.hasPrefix("-") {
                removed += 1
            }
        }

        return LineDiffStats(added: added, removed: removed)
    }
}
