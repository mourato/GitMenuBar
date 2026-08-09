import Foundation

enum GitDiffHunkParser {
    static func parse(path: String, diff: String) -> [AtomicCommitHunk] {
        let lines = diff.components(separatedBy: "\n")
        guard lines.contains(where: { $0.hasPrefix("@@ ") }) else { return [] }
        guard let firstHunk = lines.firstIndex(where: { $0.hasPrefix("@@ ") }) else { return [] }
        let prefix = Array(lines[..<firstHunk]).joined(separator: "\n") + "\n"
        guard prefix.contains("diff --git "), prefix.contains("--- "), prefix.contains("+++ ") else { return [] }

        var result: [AtomicCommitHunk] = []
        var start = firstHunk
        while start < lines.count {
            guard lines[start].hasPrefix("@@ ") else { break }
            let header = lines[start]
            guard let range = parseRange(header) else { return [] }
            let end = lines[(start + 1)...].firstIndex(where: { $0.hasPrefix("@@ ") }) ?? lines.count
            let body = Array(lines[start ..< end])
            guard body.dropFirst().allSatisfy({ $0.isEmpty || $0.hasPrefix(" ") || $0.hasPrefix("+") || $0.hasPrefix("-") || $0.hasPrefix("\\") }) else { return [] }
            let additions = body.dropFirst().filter { $0.hasPrefix("+") }.count
            let removals = body.dropFirst().filter { $0.hasPrefix("-") }.count
            let patch = prefix + body.joined(separator: "\n") + "\n"
            result.append(AtomicCommitHunk(
                id: "\(path)#hunk-\(result.count + 1)",
                path: path,
                ordinal: result.count + 1,
                header: header,
                additions: additions,
                removals: removals,
                patch: patch
            ))
            guard range.oldCount >= 0, range.newCount >= 0 else { return [] }
            start = end
        }
        return result
    }

    private static func parseRange(_ header: String) -> (oldCount: Int, newCount: Int)? {
        let parts = header.split(separator: " ")
        guard parts.count >= 4,
              let old = parseCount(String(parts[1])),
              let new = parseCount(String(parts[2])) else { return nil }
        return (old, new)
    }

    private static func parseCount(_ value: String) -> Int? {
        let value = value.dropFirst()
        let pieces = value.split(separator: ",")
        guard let start = Int(pieces[0]) else { return nil }
        return pieces.count == 1 ? 1 : Int(pieces[1])
    }
}
