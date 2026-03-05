import Foundation

final class AICommitMessageService {
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

        let (effectiveScope, diff, truncationNotice) = try await resolveDiff(
            for: selectedScope,
            gitManager: gitManager,
            preferredScopeMode: preferredScopeMode,
            overrideScope: overrideScope
        )

        let prompt = buildPrompt(
            diff: diff,
            scope: effectiveScope,
            truncationNotice: truncationNotice
        )

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

    private func resolveDiff(
        for selectedScope: DiffScope,
        gitManager: GitManager,
        preferredScopeMode: AICommitDefaultScopeMode,
        overrideScope: DiffScope?
    ) async throws -> (DiffScope, String, String?) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var effectiveScope = selectedScope
                var diff = self.diff(for: selectedScope, gitManager: gitManager)

                if overrideScope == nil,
                   preferredScopeMode == .stagedWithFallbackAll,
                   selectedScope == .staged,
                   diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    effectiveScope = .all
                    diff = self.diff(for: .all, gitManager: gitManager)
                }

                let normalizedDiff = diff.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedDiff.isEmpty else {
                    continuation.resume(throwing: AIError.noDiffAvailable)
                    return
                }

                let result = self.truncate(diff: normalizedDiff)
                continuation.resume(returning: (effectiveScope, result.diff, result.notice))
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

    private func truncate(diff: String) -> (diff: String, notice: String?) {
        guard diff.count > maxDiffCharacters else {
            return (diff, nil)
        }

        let truncated = String(diff.prefix(maxDiffCharacters))
        let notice = "Diff truncated to \(maxDiffCharacters) characters from \(diff.count) characters."
        return (truncated, notice)
    }

    private func buildPrompt(diff: String, scope: DiffScope, truncationNotice: String?) -> String {
        var sections: [String] = [
            "Generate a Conventional Commit message in English based on the git diff.",
            "Output rules:",
            "1. First line must be \"type(scope): subject\" or \"type: subject\".",
            "2. Keep subject under 72 chars, imperative mood.",
            "3. Add a blank line then body bullets describing what changed and why.",
            "4. Return plain text only, no markdown code fences.",
            "5. Do not include explanations outside the commit message.",
            "",
            "Diff scope used: \(scope.title)."
        ]

        if let truncationNotice {
            sections.append(truncationNotice)
        }

        sections.append(contentsOf: ["", "Diff:", diff])
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
