import Foundation

final class CommitHistoryParser {
    private let runner: GitCommandRunner
    private let recordSeparator = Character("\u{1e}")
    private let fieldSeparator = Character("\u{1f}")
    private let groupSeparator = Character("\u{1d}")

    init(runner: GitCommandRunner) {
        self.runner = runner
    }

    func fetchCommitHistory(in repositoryPath: String, limit: Int = 100) -> [Commit] {
        let format = "%x1e%H%x1f%h%x1f%at%x1f%an%x1f%ae%x1f%s%x1f%B%x1d"
        let args = [
            "log",
            "--reflog",
            "--date-order",
            "--pretty=format:\(format)",
            "--numstat",
            "--no-renames",
            "HEAD",
            "-n",
            String(limit)
        ]

        let result = runner.runGitCommand(in: repositoryPath, args: args)
        guard !result.failure else {
            return []
        }

        return parse(result.output)
    }

    func parse(_ output: String) -> [Commit] {
        var commits: [Commit] = []
        var seenHashes = Set<String>()

        for record in output.split(separator: recordSeparator, omittingEmptySubsequences: true) {
            let sections = record.split(separator: groupSeparator, maxSplits: 1, omittingEmptySubsequences: false)
            guard sections.count == 2 else {
                continue
            }

            let metadata = sections[0]
            let fields = metadata.split(separator: fieldSeparator, maxSplits: 6, omittingEmptySubsequences: false)
            guard fields.count == 7 else {
                continue
            }

            let hash = String(fields[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hash.isEmpty, !seenHashes.contains(hash) else {
                continue
            }

            let subject = String(fields[5]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard shouldIncludeCommit(subject: subject) else {
                continue
            }

            guard let timestamp = TimeInterval(String(fields[2]).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                continue
            }

            seenHashes.insert(hash)
            let (stats, changedFiles) = parseStats(String(sections[1]))

            commits.append(
                Commit(
                    id: hash,
                    shortHash: String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines),
                    subject: subject,
                    body: String(fields[6]).trimmingCharacters(in: .whitespacesAndNewlines),
                    authorName: String(fields[3]).trimmingCharacters(in: .whitespacesAndNewlines),
                    authorEmail: String(fields[4]).trimmingCharacters(in: .whitespacesAndNewlines),
                    committedAt: Date(timeIntervalSince1970: timestamp),
                    stats: stats,
                    changedFiles: changedFiles
                )
            )
        }

        return commits
    }

    private func parseStats(_ rawStats: String) -> (CommitStats, [CommitFileChange]) {
        var filesChanged = 0
        var insertions = 0
        var deletions = 0
        var changedFiles: [CommitFileChange] = []

        for line in rawStats.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            let components = trimmedLine.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard components.count == 3 else {
                continue
            }

            filesChanged += 1
            let added = Int(components[0]) ?? 0
            let removed = Int(components[1]) ?? 0
            insertions += added
            deletions += removed
            changedFiles.append(
                CommitFileChange(
                    path: String(components[2]),
                    lineDiff: LineDiffStats(added: added, removed: removed)
                )
            )
        }

        return (
            CommitStats(filesChanged: filesChanged, insertions: insertions, deletions: deletions),
            changedFiles
        )
    }

    private func shouldIncludeCommit(subject: String) -> Bool {
        !subject.contains("ref=refs/t3/checkpoints/")
    }
}
