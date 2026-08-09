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

final class AICommitGrouperService: ObservableObject, @unchecked Sendable {
    private let aiService: AtomicGroupingAIProviding
    private let messagePolicy: CommitMessagePolicy

    init(
        aiService: AtomicGroupingAIProviding,
        messagePolicy: CommitMessagePolicy = .shared
    ) {
        self.aiService = aiService
        self.messagePolicy = messagePolicy
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
        } catch let error as AIError {
            if case .messagePolicyRejected = error {
                throw error
            }
            return AtomicCommitGroup.fallbackGroups(for: changedFiles)
        } catch {
            return AtomicCommitGroup.fallbackGroups(for: changedFiles)
        }
    }

    func generateAtomicHunkGroups(
        snapshot: AtomicCommitSnapshot,
        provider: AIProviderConfig,
        apiKey: String,
        model: String
    ) async throws -> [AtomicCommitGroup] {
        let prompt = buildHunkGroupingPrompt(snapshot: snapshot)
        do {
            let response = try await aiService.generateRawResponse(prompt: prompt, provider: provider, apiKey: apiKey, model: model)
            let groups = try parseHunkGroupsFromResponse(response, snapshot: snapshot)
            guard !groups.isEmpty else { return AtomicCommitGroup.fallbackGroups(for: snapshot.files) }
            return groups
        } catch let error as AIError {
            if case .messagePolicyRejected = error {
                throw error
            }
            return AtomicCommitGroup.fallbackGroups(for: snapshot.files)
        } catch {
            return AtomicCommitGroup.fallbackGroups(for: snapshot.files)
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
           let decoded = try? decoder.decode([RawAtomicGroup].self, from: data)
        {
            rawGroups = decoded
        } else if let extracted = extractJSONArray(from: cleaned),
                  let decoded = try? decoder.decode([RawAtomicGroup].self, from: extracted)
        {
            rawGroups = decoded
        } else {
            throw AIError.invalidResponse
        }

        var groups: [AtomicCommitGroup] = []
        for raw in rawGroups {
            let files = raw.files.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !files.isEmpty else { continue }
            let message = raw.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let acceptedMessage: String
            switch messagePolicy.sanitize(message) {
            case let .success(sanitized):
                acceptedMessage = sanitized
            case let .failure(error):
                throw error.aiError
            }
            groups.append(AtomicCommitGroup(files: files, message: acceptedMessage))
        }
        return groups
    }

    func parseHunkGroupsFromResponse(
        _ response: String,
        snapshot: AtomicCommitSnapshot
    ) throws -> [AtomicCommitGroup] {
        let cleaned = strippingCodeFences(from: response)
        let data = cleaned.data(using: .utf8) ?? extractJSONArray(from: cleaned)
        guard let data, let rawGroups = try? JSONDecoder().decode([RawAtomicGroup].self, from: data) else {
            throw AIError.invalidResponse
        }
        let groups = try rawGroups.compactMap { raw -> AtomicCommitGroup? in
            let files = raw.files.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let hunks = raw.hunks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !files.isEmpty || !hunks.isEmpty else { return nil }
            let message: String
            switch messagePolicy.sanitize(raw.message.trimmingCharacters(in: .whitespacesAndNewlines)) {
            case let .success(sanitized): message = sanitized
            case let .failure(error): throw error.aiError
            }
            return AtomicCommitGroup(files: files, hunks: hunks, message: message)
        }
        do {
            let plan = try AtomicCommitPlan(groups: groups, allowedFiles: snapshot.allowedFiles, hunksByID: snapshot.hunksByID)
            let completeFiles = Set(plan.groups.flatMap(\.files))
            let selectedHunks = Set(plan.groups.flatMap(\.hunks))
            let selectedHunkPaths = Set(selectedHunks.compactMap { snapshot.hunksByID[$0]?.path })
            guard completeFiles.isDisjoint(with: selectedHunkPaths) else { throw AIError.invalidResponse }
            guard Set(snapshot.files.map(\.path)) == completeFiles.union(selectedHunkPaths) else { throw AIError.invalidResponse }
            return plan.groups
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.invalidResponse
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
    let hunks: [String]
    let message: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decodeIfPresent([String].self, forKey: .files) ?? []
        hunks = try container.decodeIfPresent([String].self, forKey: .hunks) ?? []
        message = try container.decode(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case files, hunks, message
    }
}
