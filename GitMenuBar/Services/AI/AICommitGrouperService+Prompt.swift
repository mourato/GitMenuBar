import Foundation

extension AICommitGrouperService {
    private static let maxHunkGroupingPromptCharacters = 40000
    private static let maxHunkMetadataCharacters = 12000

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

    func buildHunkGroupingPrompt(snapshot: AtomicCommitSnapshot) -> String {
        let instructions = [
            "Group the changed files and ordinary text hunks into atomic commits.",
            "A complete file belongs in files. A splittable hunk belongs in hunks using its exact ID.",
            "The same hunk ID may appear at most once. A path may repeat only through distinct hunk IDs.",
            "Respond with ONLY a JSON array of {\"files\":[...],\"hunks\":[...],\"message\":\"type: subject\"}.",
            "Every changed path must be selected exactly once, either as a complete file or through all of its listed hunks.",
            ""
        ].joined(separator: "\n")
        var fileSections: [String] = []
        for file in snapshot.files.sorted(by: { $0.path < $1.path }) {
            let hunks = snapshot.hunks.filter { $0.path == file.path }
            if hunks.isEmpty {
                fileSections.append("FILE \(file.path)")
            } else {
                fileSections.append("FILE \(file.path) (select hunks, or the complete file)")
            }
        }

        let metadata = snapshot.hunks.map { hunk in
            "- \(hunk.id): \(hunk.path) \(hunk.header) (+\(hunk.additions)/-\(hunk.removals))"
        }
        let metadataSection = boundedHunkMetadata(metadata)
        let prefix = [instructions, fileSections.joined(separator: "\n"), "", "HUNK METADATA:", metadataSection]
            .joined(separator: "\n")
        let patchIntro = "\n\nHUNK PATCHES:\n"
        let patchBudget = max(0, Self.maxHunkGroupingPromptCharacters - prefix.count - patchIntro.count)
        let omissionMarker = "[HUNK PATCH CONTENT OMITTED: per-hunk budget was too small for the patch header.]"
        let contentBudget = max(0, patchBudget - omissionMarker.count - 32)
        var omittedHunkCount = 0
        var omittedPatchCharacters = 0
        let patchSections = snapshot.hunks.enumerated().compactMap { index, hunk -> String? in
            let budget = snapshot.hunks.isEmpty ? 0 : contentBudget / snapshot.hunks.count
            guard let section = boundedHunkPatch(hunk, budget: budget, ordinal: index + 1) else {
                omittedHunkCount += 1
                omittedPatchCharacters += hunk.patch.count
                return nil
            }
            return section
        }
        var patchContent = patchSections.joined(separator: "\n")
        if omittedHunkCount > 0 {
            patchContent += "\(patchContent.isEmpty ? "" : "\n")\(omissionMarker) (\(omittedHunkCount) hunks, \(omittedPatchCharacters) patch characters omitted)"
        }
        return String((prefix + patchIntro + patchContent).prefix(Self.maxHunkGroupingPromptCharacters))
    }

    private func boundedHunkMetadata(_ metadata: [String]) -> String {
        guard !metadata.isEmpty else { return "(none)" }
        let marker = "[HUNK METADATA OMITTED: additional hunk metadata omitted because the prompt budget is bounded.]"
        let markerReserve = marker.count + 32
        var result = ""
        for (index, line) in metadata.enumerated() {
            let addition = result.isEmpty ? line : "\n\(line)"
            if result.count + addition.count + (index == metadata.count - 1 ? 0 : markerReserve + 1) > Self.maxHunkMetadataCharacters {
                let omittedCount = metadata.count - index
                let omission = "\(marker) (\(omittedCount) hunks omitted)"
                if result.count + (result.isEmpty ? 0 : 1) + omission.count <= Self.maxHunkMetadataCharacters {
                    result += result.isEmpty ? omission : "\n\(omission)"
                }
                break
            }
            result += addition
        }
        return result
    }

    private func boundedHunkPatch(_ hunk: AtomicCommitHunk, budget: Int, ordinal: Int) -> String? {
        let prefix = "HUNK \(ordinal) PATCH \(hunk.id) [\(hunk.path)]\n"
        guard budget >= prefix.count else { return nil }
        guard !hunk.patch.isEmpty else {
            return prefix + "PATCH: (empty)"
        }

        let complete = prefix + hunk.patch
        guard complete.count > budget else { return complete }

        let omittedMarker = { (omitted: Int) in
            "PATCH: [truncated; omitted \(omitted) characters]"
        }
        var contentLength = max(0, budget - prefix.count - omittedMarker(hunk.patch.count).count)
        var marker = omittedMarker(hunk.patch.count - contentLength)
        while prefix.count + contentLength + marker.count > budget, contentLength > 0 {
            contentLength -= 1
            marker = omittedMarker(hunk.patch.count - contentLength)
        }
        return prefix + String(hunk.patch.prefix(contentLength)) + marker
    }
}
