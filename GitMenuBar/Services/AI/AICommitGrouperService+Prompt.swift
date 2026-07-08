import Foundation

extension AICommitGrouperService {
    func buildGroupingPrompt(
        changedFiles: [WorkingTreeFile],
        diffPerFile: [String: String]
    ) -> String {
        var sections: [String] = [
            "You are helping create atomic (one-logical-change-per-commit) Git commits.",
            "Analyze the per-file diffs below and group the files into logical commits.",
            "",
            "Grouping rules:",
            "1. Files that belong to the same logical change (same feature, fix, refactor, or concern) go in one group.",
            "2. Keep unrelated changes in separate groups (e.g. a bugfix should not be mixed with a style change).",
            "3. Each group needs a Conventional Commit message: \"type(scope): subject\".",
            "   Use types like feat, fix, refactor, chore, docs, test, style, perf.",
            "4. Keep the subject under 72 characters, imperative mood.",
            "",
            "Respond with ONLY a JSON array, no markdown, no commentary. Format:",
            "[",
            "  {\"files\": [\"path/to/file.swift\"], \"message\": \"feat: add new endpoint\"},",
            "  {\"files\": [\"path/to/helper.swift\"], \"message\": \"refactor: extract helper\"}",
            "]",
            "Every changed file must appear in exactly one group. Paths must match the file paths below exactly.",
            ""
        ]

        let sortedFiles = changedFiles.sorted { $0.path < $1.path }

        sections.append("Changed files (\(changedFiles.count)):")
        for file in sortedFiles {
            sections.append("- \(file.path)")
        }

        sections.append("")
        sections.append("Diffs:")
        for file in sortedFiles {
            let diff = diffPerFile[file.path] ?? "(no diff available)"
            sections.append("")
            sections.append("=== \(file.path) ===")
            sections.append(diff)
        }

        return sections.joined(separator: "\n")
    }
}
