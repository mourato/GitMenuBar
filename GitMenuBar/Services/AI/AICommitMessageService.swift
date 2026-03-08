import Foundation

final class AICommitMessageService {
    private struct ParsedDiffSection {
        let path: String
        let content: String
        let lineDiff: LineDiffStats
    }

    private struct IncludedDiffSnippet {
        let path: String
        let content: String
        let truncated: Bool
    }

    private struct OverflowSummary {
        let path: String
        let lineDiff: LineDiffStats
        let omittedCharacters: Int
    }

    private struct StructuredDiffPayload {
        let scope: DiffScope
        let includedSnippets: [IncludedDiffSnippet]
        let overflowSummaries: [OverflowSummary]
        let filePathsInScope: [String]
        let totalCharacters: Int
        let includedCharacters: Int
        let truncationNotice: String?
    }

    private static let diffHeaderRegex = try? NSRegularExpression(
        pattern: #"^diff --git (?:"a/(.+)"|a/(\S+)) (?:"b/(.+)"|b/(\S+))$"#
    )

    private let maxDiffCharacters: Int
    private let session: URLSession

    init(maxDiffCharacters: Int = 40000, session: URLSession = .shared) {
        self.maxDiffCharacters = maxDiffCharacters
        self.session = session
    }

    func testConnection(
        providerType: AIProviderType,
        endpointURL: String,
        apiKey: String
    ) async throws -> [String] {
        let config = AIProviderConfig(
            name: "temp",
            type: providerType,
            endpointURL: endpointURL,
            selectedModel: ""
        )

        let adapter = AIProviderAdapterFactory.makeAdapter(for: providerType)
        try await adapter.testConnection(config: config, apiKey: apiKey, session: session)
        return try await adapter.fetchModels(config: config, apiKey: apiKey, session: session)
    }

    func generateCommitMessage(
        provider: AIProviderConfig,
        apiKey: String,
        model: String,
        preferredScopeMode: AICommitDefaultScopeMode,
        overrideScope: DiffScope?,
        gitManager: GitManager
    ) async throws -> String {
        let selectedScope = resolveRequestedScope(
            preferredScopeMode: preferredScopeMode,
            overrideScope: overrideScope
        )

        let payload = try await resolveDiffPayload(
            for: selectedScope,
            gitManager: gitManager,
            preferredScopeMode: preferredScopeMode,
            overrideScope: overrideScope
        )

        let prompt = buildPrompt(payload: payload)

        let adapter = AIProviderAdapterFactory.makeAdapter(for: provider.type)
        let rawResponse = try await adapter.generateCommitMessage(
            config: provider,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
            session: session
        )

        let cleanedResponse = cleanCommitMessage(rawResponse)
        guard !cleanedResponse.isEmpty else {
            throw AIError.emptyResponse
        }

        return cleanedResponse
    }

    private func resolveRequestedScope(
        preferredScopeMode: AICommitDefaultScopeMode,
        overrideScope: DiffScope?
    ) -> DiffScope {
        if let overrideScope {
            return overrideScope
        }

        switch preferredScopeMode {
        case .stagedWithFallbackAll:
            return .staged
        }
    }

    private func resolveDiffPayload(
        for selectedScope: DiffScope,
        gitManager: GitManager,
        preferredScopeMode: AICommitDefaultScopeMode,
        overrideScope: DiffScope?
    ) async throws -> StructuredDiffPayload {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var effectiveScope = selectedScope
                var rawDiff = self.diff(for: selectedScope, gitManager: gitManager)

                if overrideScope == nil,
                   preferredScopeMode == .stagedWithFallbackAll,
                   selectedScope == .staged,
                   rawDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    effectiveScope = .all
                    rawDiff = self.diff(for: .all, gitManager: gitManager)
                }

                let normalizedDiff = rawDiff.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedDiff.isEmpty else {
                    continuation.resume(throwing: AIError.noDiffAvailable)
                    return
                }

                let payload = self.assemblePayload(
                    scope: effectiveScope,
                    rawDiff: normalizedDiff
                )
                continuation.resume(returning: payload)
            }
        }
    }

    private func diff(for scope: DiffScope, gitManager: GitManager) -> String {
        switch scope {
        case .staged:
            return gitManager.diffStaged()
        case .unstaged:
            return gitManager.diffUnstaged()
        case .all:
            return gitManager.diffAll()
        }
    }

    private func assemblePayload(scope: DiffScope, rawDiff: String) -> StructuredDiffPayload {
        let sections = parseSections(from: rawDiff).sorted { lhs, rhs in
            lhs.path < rhs.path
        }

        if sections.isEmpty {
            let fallback = ParsedDiffSection(
                path: "working-tree",
                content: rawDiff,
                lineDiff: lineDiff(for: rawDiff)
            )
            return assemblePayload(scope: scope, sections: [fallback])
        }

        return assemblePayload(scope: scope, sections: sections)
    }

    private func assemblePayload(scope: DiffScope, sections: [ParsedDiffSection]) -> StructuredDiffPayload {
        let totalCharacters = sections.reduce(0) { $0 + $1.content.count }
        let fileCount = sections.count
        let baselineReserve = fileCount == 0 ? 0 : min(220, maxDiffCharacters / max(fileCount, 1))

        var consumed = Array(repeating: 0, count: fileCount)
        var snippets = Array(repeating: "", count: fileCount)
        var usedCharacters = 0

        if maxDiffCharacters > 0 {
            for index in sections.indices {
                guard usedCharacters < maxDiffCharacters else { break }

                let content = sections[index].content
                let initialTake = min(baselineReserve, content.count)
                if initialTake <= 0 {
                    continue
                }

                let take = min(initialTake, maxDiffCharacters - usedCharacters)
                snippets[index] = String(content.prefix(take))
                consumed[index] = take
                usedCharacters += take
            }

            while usedCharacters < maxDiffCharacters {
                let pendingIndices = sections.indices.filter { consumed[$0] < sections[$0].content.count }
                if pendingIndices.isEmpty {
                    break
                }

                let remainingBudget = maxDiffCharacters - usedCharacters
                let share = max(80, remainingBudget / pendingIndices.count)
                var wroteAnySlice = false

                for index in pendingIndices {
                    if usedCharacters >= maxDiffCharacters {
                        break
                    }

                    let content = sections[index].content
                    let remainingInSection = content.count - consumed[index]
                    guard remainingInSection > 0 else {
                        continue
                    }

                    let take = min(share, remainingInSection, maxDiffCharacters - usedCharacters)
                    guard take > 0 else {
                        continue
                    }

                    let start = content.index(content.startIndex, offsetBy: consumed[index])
                    let end = content.index(start, offsetBy: take)
                    snippets[index].append(contentsOf: content[start ..< end])
                    consumed[index] += take
                    usedCharacters += take
                    wroteAnySlice = true
                }

                if !wroteAnySlice {
                    break
                }
            }
        }

        let includedSnippets = sections.indices.compactMap { index -> IncludedDiffSnippet? in
            let snippet = snippets[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !snippet.isEmpty else {
                return nil
            }

            let truncated = consumed[index] < sections[index].content.count
            return IncludedDiffSnippet(
                path: sections[index].path,
                content: snippet,
                truncated: truncated
            )
        }

        let overflowSummaries = sections.indices.compactMap { index -> OverflowSummary? in
            let omittedCharacters = max(0, sections[index].content.count - consumed[index])
            guard omittedCharacters > 0 else {
                return nil
            }

            return OverflowSummary(
                path: sections[index].path,
                lineDiff: sections[index].lineDiff,
                omittedCharacters: omittedCharacters
            )
        }

        let effectiveIncludedCharacters = consumed.reduce(0, +)
        let truncationNotice: String? = {
            guard effectiveIncludedCharacters < totalCharacters else { return nil }
            return "Diff truncated to \(effectiveIncludedCharacters) characters from \(totalCharacters) characters across \(fileCount) files."
        }()

        return StructuredDiffPayload(
            scope: scope,
            includedSnippets: includedSnippets,
            overflowSummaries: overflowSummaries,
            filePathsInScope: sections.map(\.path),
            totalCharacters: totalCharacters,
            includedCharacters: effectiveIncludedCharacters,
            truncationNotice: truncationNotice
        )
    }

    private func parseSections(from diff: String) -> [ParsedDiffSection] {
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

    private func parsePath(fromDiffHeader header: String) -> String? {
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

    private func lineDiff(for section: String) -> LineDiffStats {
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

    private func buildPrompt(payload: StructuredDiffPayload) -> String {
        var sections: [String] = [
            "Generate a Conventional Commit message in English based on the git diff.",
            "Output rules:",
            "1. First line must be \"type(scope): subject\" or \"type: subject\".",
            "2. Keep subject under 72 chars, imperative mood.",
            "3. Add a blank line then body bullets describing what changed and why.",
            "4. Return plain text only, no markdown code fences.",
            "5. Do not include explanations outside the commit message.",
            "",
            "Diff scope used: \(payload.scope.title).",
            "Files in scope (\(payload.filePathsInScope.count)): \(payload.filePathsInScope.joined(separator: ", "))."
        ]

        if let truncationNotice = payload.truncationNotice {
            sections.append(truncationNotice)
        }

        if !payload.overflowSummaries.isEmpty {
            sections.append("")
            sections.append("Overflow summary:")
            for summary in payload.overflowSummaries {
                sections.append("- \(summary.path) (+\(summary.lineDiff.added) -\(summary.lineDiff.removed), omitted \(summary.omittedCharacters) chars)")
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

    func cleanCommitMessage(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```text", with: "")
                .replacingOccurrences(of: "```markdown", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleaned.lowercased().hasPrefix("commit message:") {
            cleaned = cleaned
                .replacingOccurrences(of: "commit message:", with: "", options: [.caseInsensitive, .anchored])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }
}
