import Foundation

protocol AtomicGroupingAIProviding {
    func generateRawResponse(
        prompt: String,
        provider: AIProviderConfig,
        apiKey: String,
        model: String
    ) async throws -> String
}

extension AICommitMessageService: AtomicGroupingAIProviding {}

final class AICommitGrouperService: ObservableObject {
    private let aiService: AtomicGroupingAIProviding

    init(aiService: AtomicGroupingAIProviding) {
        self.aiService = aiService
    }

    /// Analyze per-file diffs and group them into logical atomic commits.
    /// Returns groups with suggested messages, or falls back to one group per file
    /// when the AI fails or returns invalid JSON.
    func generateAtomicGroups(
        changedFiles: [WorkingTreeFile],
        diffPerFile: [String: String],
        provider: AIProviderConfig,
        apiKey: String,
        model: String
    ) async throws -> [AtomicCommitGroup] {
        let prompt = buildGroupingPrompt(changedFiles: changedFiles, diffPerFile: diffPerFile)

        do {
            let response = try await aiService.generateRawResponse(
                prompt: prompt,
                provider: provider,
                apiKey: apiKey,
                model: model
            )
            let groups = try parseGroupsFromResponse(response)
            guard !groups.isEmpty else {
                return AtomicCommitGroup.fallbackGroups(for: changedFiles)
            }
            return groups
        } catch {
            return AtomicCommitGroup.fallbackGroups(for: changedFiles)
        }
    }

    /// Partition an existing set of groups: move `file` from `source` to `target`.
    static func moveFile(
        _ file: String,
        from source: inout AtomicCommitGroup,
        to target: inout AtomicCommitGroup
    ) {
        source.files.removeAll { $0 == file }
        if !target.files.contains(file) {
            target.files.append(file)
        }
    }

    func parseGroupsFromResponse(
        _ response: String
    ) throws -> [AtomicCommitGroup] {
        let cleaned = strippingCodeFences(from: response)
        let decoder = JSONDecoder()

        let rawGroups: [RawAtomicGroup]
        if let data = cleaned.data(using: .utf8),
           let decoded = try? decoder.decode([RawAtomicGroup].self, from: data) {
            rawGroups = decoded
        } else if let extracted = extractJSONArray(from: cleaned),
                  let decoded = try? decoder.decode([RawAtomicGroup].self, from: extracted) {
            rawGroups = decoded
        } else {
            throw AIError.invalidResponse
        }

        return rawGroups.compactMap { raw -> AtomicCommitGroup? in
            let files = raw.files.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !files.isEmpty else { return nil }
            let message = raw.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return AtomicCommitGroup(files: files, message: message)
        }
    }

    private func strippingCodeFences(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func extractJSONArray(from text: String) -> Data? {
        let ns = text as NSString
        let startRange = ns.range(of: "[")
        let endRange = ns.range(of: "]", options: .backwards)
        guard startRange.location != NSNotFound, endRange.location != NSNotFound else {
            return nil
        }
        let length = endRange.location - startRange.location + 1
        guard length > 0 else { return nil }
        let json = ns.substring(with: NSRange(location: startRange.location, length: length))
        return json.data(using: .utf8)
    }
}

private struct RawAtomicGroup: Codable {
    let files: [String]
    let message: String
}
