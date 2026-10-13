import Foundation
import Synchronization

// models.dev catalog types and the on-disk pricing cache used by the monthly
// spend estimate. Ported from CodexBar's `ModelsDevPricing.swift` (MIT,
// Peter Steinberger — see THIRD-PARTY-NOTICES.md), simplified: no custom
// pricing overlay, no historical pricing, no fallback merging. models.dev
// publishes USD per 1M tokens; consumers divide by 1M.

/// A long-context rate block; implies a 200K-token threshold.
struct ModelsDevContextCost: Codable, Equatable, Sendable {
    let input: Double?
    let output: Double?
    let cacheRead: Double?
    let cacheWrite: Double?

    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }
}

/// USD per 1M tokens, straight from a catalog `cost` block.
struct ModelsDevCost: Codable, Equatable, Sendable {
    let input: Double?
    let output: Double?
    let cacheRead: Double?
    let cacheWrite: Double?
    let contextOver200K: ModelsDevContextCost?

    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case contextOver200K = "context_over_200k"
    }
}

struct ModelsDevModel: Codable, Equatable, Sendable {
    let id: String
    let name: String?
    let cost: ModelsDevCost?

    var isPriceable: Bool {
        cost?.input != nil && cost?.output != nil
    }
}

struct ModelsDevProvider: Codable, Equatable, Sendable {
    let id: String?
    let name: String?
    let models: [String: ModelsDevModel]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case models
    }

    init(id: String?, name: String?, models: [String: ModelsDevModel]) {
        self.id = id
        self.name = name
        self.models = models
    }

    /// Models are keyed arbitrarily in the live catalog, so decode them
    /// tolerantly and skip entries that do not fit the shape.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)

        let modelContainer = try container.nestedContainer(
            keyedBy: ModelsDevAnyCodingKey.self,
            forKey: .models
        )
        var models: [String: ModelsDevModel] = [:]
        for key in modelContainer.allKeys {
            guard let model = try? modelContainer.decode(ModelsDevModel.self, forKey: key) else { continue }
            models[key.stringValue] = model
        }
        self.models = models
    }
}

struct ModelsDevCatalog: Codable, Equatable, Sendable {
    let providers: [String: ModelsDevProvider]

    /// The live api.json is a flat provider-key map; a `{"providers": …}`
    /// wrapper is tolerated the same way CodexBar does.
    init(providers: [String: ModelsDevProvider]) {
        self.providers = providers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: ModelsDevAnyCodingKey.self)
        if let providersKey = ModelsDevAnyCodingKey(stringValue: "providers"),
           let decoded = try? container.decode([String: ModelsDevProvider].self, forKey: providersKey)
        {
            providers = decoded
            return
        }

        var providers: [String: ModelsDevProvider] = [:]
        for key in container.allKeys {
            guard let provider = try? container.decode(ModelsDevProvider.self, forKey: key) else { continue }
            providers[key.stringValue] = provider
        }
        self.providers = providers
    }

    func model(providerID: String, rawModelID: String) -> ModelsDevModel? {
        guard let provider = providers[providerID] ?? providers[providerID.lowercased()] else { return nil }
        for candidate in UsageQuotaModelsDev.modelIDCandidates(rawModelID) {
            if let model = provider.models[candidate] {
                return model
            }
            for match in provider.models.values where match.id == candidate {
                return match
            }
        }
        return nil
    }

    /// Direct pricing sources must both be present and priceable; this
    /// rejects empty or partial responses before they replace a cache.
    func isPlausibleRefresh() -> Bool {
        ["anthropic", "openai"].allSatisfy { providerID in
            providers[providerID]?.models.values.contains(where: \.isPriceable) == true
        }
    }
}

private struct ModelsDevAnyCodingKey: CodingKey {
    var intValue: Int?
    var stringValue: String

    init?(intValue: Int) {
        self.intValue = intValue
        stringValue = String(intValue)
    }

    init?(stringValue: String) {
        intValue = nil
        self.stringValue = stringValue
    }
}

enum UsageQuotaModelsDev {
    /// Model-ID lookup candidates, ported from CodexBar's
    /// `ModelsDevModelIDNormalizer.candidates`: provider prefixes, Claude
    /// aliases, dated snapshots, and `-vN:N` suffixes all collapse toward a
    /// base ID that the catalog may key.
    static func modelIDCandidates(_ raw: String) -> [String] {
        var candidates: [String] = []

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        append(trimmed)
        appendProviderStrippedCandidates(trimmed, to: append)
        appendClaudeDotTailCandidate(trimmed, to: append)

        var index = 0
        while index < candidates.count {
            appendSuffixAliasCandidates(candidates[index], to: append)
            index += 1
        }
        return candidates
    }

    private static func appendProviderStrippedCandidates(_ raw: String, to append: (String) -> Void) {
        if raw.hasPrefix("openai/") {
            append(String(raw.dropFirst("openai/".count)))
        }
        if raw.hasPrefix("anthropic.") {
            append(String(raw.dropFirst("anthropic.".count)))
        }
    }

    private static func appendClaudeDotTailCandidate(_ raw: String, to append: (String) -> Void) {
        guard let lastDot = raw.lastIndex(of: "."), raw.contains("claude-") else { return }
        let tail = String(raw[raw.index(after: lastDot)...])
        if tail.hasPrefix("claude-") {
            append(tail)
        }
    }

    private static func appendSuffixAliasCandidates(_ candidate: String, to append: (String) -> Void) {
        if let atSign = candidate.firstIndex(of: "@") {
            let base = String(candidate[..<atSign])
            let suffix = String(candidate[candidate.index(after: atSign)...])
            if suffix.range(of: #"^\d{8}$"#, options: .regularExpression) != nil {
                append("\(base)-\(suffix)")
            }
            append(base)
        } else if candidate.hasPrefix("claude-") {
            append("\(candidate)@default")
        }

        if let dated = candidate.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            append(String(candidate[..<dated.lowerBound]))
        }
        if let compactDate = candidate.range(of: #"-\d{8}$"#, options: .regularExpression) {
            append(String(candidate[..<compactDate.lowerBound]))
        }
        if let version = candidate.range(of: #"-v\d+:\d+$"#, options: .regularExpression) {
            var base = candidate
            base.removeSubrange(version)
            append(base)
        }
    }
}

/// Disk-backed models.dev cache: payload JSON plus a small metadata file,
/// memoized by (mtime, size) so a scan decodes the catalog once.
enum UsageQuotaModelsDevStore {
    /// The resolved pricing source for one cost scan.
    struct PricingSource: Equatable, Sendable {
        let catalog: ModelsDevCatalog?
        /// Cache key for per-file cost totals; totals computed against a
        /// different source token must be rescanned.
        let token: String

        static let bundled = PricingSource(catalog: nil, token: "bundled")
    }

    struct CacheArtifacts: Equatable, Sendable {
        let catalog: ModelsDevCatalog
        let fetchedAt: Date
    }

    static let endpoint = URL(string: "https://models.dev/api.json")!
    static let ttl: TimeInterval = 24 * 60 * 60
    private static let artifactVersion = 1
    private static let requestTimeout: TimeInterval = 30

    private struct ArtifactMeta: Codable {
        let version: Int
        let fetchedAt: Date
    }

    private enum MemoOutcome {
        case decoded(CacheArtifacts)
        case failure
    }

    private struct MemoEntry {
        let modified: Date?
        let size: Int?
        let outcome: MemoOutcome
    }

    /// The full load outcome is memoized, not just successful decodes: a corrupt
    /// cache file is as expensive to discover as a valid one, and pricing calls
    /// run once per usage row.
    private static let memo = Mutex<MemoEntry?>(nil)

    static func payloadFileURL(cacheRoot: URL? = nil) -> URL {
        costPricingDirectory(cacheRoot: cacheRoot).appendingPathComponent("models-dev-v\(artifactVersion).json")
    }

    static func metaFileURL(cacheRoot: URL? = nil) -> URL {
        costPricingDirectory(cacheRoot: cacheRoot).appendingPathComponent("models-dev-v\(artifactVersion).meta.json")
    }

    private static func costPricingDirectory(cacheRoot: URL?) -> URL {
        let base = cacheRoot
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.mourato.GitMenuBar", isDirectory: true)
            .appendingPathComponent("model-pricing", isDirectory: true)
    }

    private static func fileMetadata(at url: URL) -> (modified: Date?, size: Int?) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (values?.contentModificationDate, values?.fileSize)
    }

    /// Decoded catalog from disk, if present and decodable; memoized by the
    /// payload file's (mtime, size).
    static func loadCached(cacheRoot: URL? = nil) -> CacheArtifacts? {
        let payloadURL = payloadFileURL(cacheRoot: cacheRoot)
        let metaURL = metaFileURL(cacheRoot: cacheRoot)
        let meta = try? JSONDecoder().decode(ArtifactMeta.self, from: Data(contentsOf: metaURL))
        let payloadMeta = fileMetadata(at: payloadURL)

        let cached = memo.withLock { entry -> CacheArtifacts? in
            guard let entry,
                  entry.modified == payloadMeta.modified,
                  entry.size == payloadMeta.size,
                  case let .decoded(artifacts) = entry.outcome
            else { return nil }
            return artifacts
        }
        if let cached, meta?.version == artifactVersion {
            return cached
        }

        guard meta?.version == artifactVersion,
              let data = try? Data(contentsOf: payloadURL),
              let catalog = try? JSONDecoder().decode(ModelsDevCatalog.self, from: data)
        else {
            memo.withLock { $0 = MemoEntry(
                modified: payloadMeta.modified,
                size: payloadMeta.size,
                outcome: .failure
            ) }
            return nil
        }
        let artifacts = CacheArtifacts(catalog: catalog, fetchedAt: meta?.fetchedAt ?? .distantPast)
        memo.withLock { $0 = MemoEntry(
            modified: payloadMeta.modified,
            size: payloadMeta.size,
            outcome: .decoded(artifacts)
        ) }
        return artifacts
    }

    /// Cached catalog when fresh; fetches when missing or stale. Network
    /// failures keep serving the stale cache, and an implausible catalog
    /// (missing priceable OpenAI or Anthropic models) never replaces a good
    /// one.
    static func loadOrFetch(
        now: Date = Date(),
        cacheRoot: URL? = nil,
        session: URLSession = .shared,
        fetch: (@Sendable () async throws -> Data)? = nil
    ) async -> PricingSource {
        if let cached = loadCached(cacheRoot: cacheRoot) {
            if now.timeIntervalSince(cached.fetchedAt) < ttl {
                return pricingSource(for: cached)
            }
        }

        let data: Data? = await {
            if let fetch {
                return try? await fetch()
            }
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = requestTimeout
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { return nil }
            return data
        }()

        if let data,
           let catalog = try? JSONDecoder().decode(ModelsDevCatalog.self, from: data),
           catalog.isPlausibleRefresh()
        {
            persist(payload: data, fetchedAt: now, cacheRoot: cacheRoot)
            return pricingSource(for: CacheArtifacts(catalog: catalog, fetchedAt: now))
        }

        if let cached = loadCached(cacheRoot: cacheRoot) {
            return pricingSource(for: cached)
        }
        return .bundled
    }

    private static func pricingSource(for artifacts: CacheArtifacts) -> PricingSource {
        PricingSource(
            catalog: artifacts.catalog,
            token: "modelsdev:\(artifactVersion):\(Int(artifacts.fetchedAt.timeIntervalSince1970))"
        )
    }

    private static func persist(payload: Data, fetchedAt: Date, cacheRoot: URL?) {
        let directory = costPricingDirectory(cacheRoot: cacheRoot)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? payload.write(to: payloadFileURL(cacheRoot: cacheRoot), options: .atomic)
        let meta = ArtifactMeta(version: artifactVersion, fetchedAt: fetchedAt)
        if let encoded = try? JSONEncoder().encode(meta) {
            try? encoded.write(to: metaFileURL(cacheRoot: cacheRoot), options: .atomic)
        }
        // The payload file changed on disk; drop the memo so the next load
        // re-reads it (Mutex is not reentrant, so invalidate outside any lock).
        memo.withLock { $0 = nil }
    }

    /// Test seam: drops the decoded-catalog memo.
    static func resetMemoForTesting() {
        memo.withLock { $0 = nil }
    }
}
