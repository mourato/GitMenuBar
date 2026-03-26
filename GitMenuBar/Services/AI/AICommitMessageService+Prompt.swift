import Foundation

extension AICommitMessageService {
    func buildPrompt(payload: StructuredDiffPayload) -> String {
        var sections: [String] = [
            "Generate a Conventional Commit message in English based on the git diff.",
            "Output rules:",
            "1. First line must be \"type(scope): subject\" or \"type: subject\".",
            "2. Keep subject under 72 chars, imperative mood.",
            "3. Add a blank line then body bullets describing what changed and why.",
            "4. Return plain text only, no markdown code fences.",
            "5. Do not include explanations outside the commit message.",
            "",
            "Diff scope used: \(payload.scopeDescription).",
            "Files in scope (\(payload.filePathsInScope.count)): \(payload.filePathsInScope.joined(separator: ", "))."
        ]

        if let truncationNotice = payload.truncationNotice {
            sections.append(truncationNotice)
        }

        if !payload.overflowSummaries.isEmpty {
            sections.append("")
            sections.append("Overflow summary:")
            for summary in payload.overflowSummaries {
                sections.append(
                    "- \(summary.path) (+\(summary.lineDiff.added) -\(summary.lineDiff.removed), omitted \(summary.omittedCharacters) chars)"
                )
            }
        }

        sections.append("")
        sections.append("Included diff snippets:")
        for snippet in payload.includedSnippets {
            let marker = snippet.truncated ? " (truncated)" : ""
            sections.append("")
            sections.append("File: \(snippet.path)\(marker)")
            sections.append(snippet.content)
        }

        return sections.joined(separator: "\n")
    }
}
