import CryptoKit
import Foundation

// models.dev catalog types and the on-disk pricing cache used by the monthly
// spend estimate. Ported from CodexBar's `ModelsDevPricing.swift` (MIT,
// Peter Steinberger — see THIRD-PARTY-NOTICES.md), simplified: no custom
// pricing overlay, no historical pricing, no fallback merging. models.dev
// publishes USD per 1M tokens; consumers divide by 1M.

/// A rate block, optionally associated with an explicit context tier.
struct ModelsDevContextCost: Codable, Equatable, Sendable {
    struct Tier: Codable, Equatable, Sendable {
        let type: String
        let size: Int?
    }

    let input: Double?
    let output: Double?
    let cacheRead: Double?
    let cacheWrite: Double?
    let tier: Tier?

    var isValid: Bool {
        [input, output, cacheRead, cacheWrite].compactMap(\.self).allSatisfy { $0.isFinite && $0 >= 0 }
            && (tier?.type != "context" || (tier?.size ?? 0) > 0)
    }

    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case tier
    }
}

/// USD per 1M tokens, straight from a catalog `cost` block.
struct ModelsDevCost: Codable, Equatable, Sendable {
    let input: Double?
    let output: Double?
    let cacheRead: Double?
    let cacheWrite: Double?
    let contextOver200K: ModelsDevContextCost?
    let tiers: [ModelsDevContextCost]?

    var isValid: Bool {
        guard input != nil, output != nil else { return false }
        return [input, output, cacheRead, cacheWrite].compactMap(\.self).allSatisfy { $0.isFinite && $0 >= 0 }
            && (contextOver200K?.isValid ?? true) && (tiers?.allSatisfy(\.isValid) ?? true)
    }

    var longContext: (tokens: Int, rates: ModelsDevContextCost)? {
        if let context = tiers?.first(where: { $0.tier?.type == "context" }),
           let size = context.tier?.size
        {
            return (size, context)
        }
        return contextOver200K.map { (200_000, $0) }
    }

    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case contextOver200K = "context_over_200k"
        case tiers
    }
}

struct ModelsDevModel: Codable, Equatable, Sendable {
    let id: String
    let name: String?
    let cost: ModelsDevCost?

    var isPriceable: Bool {
        cost?.isValid == true
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
    init(from decoder: any Decoder) throws { // justified: Swift protocol existential, not a type-check suppression.
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

    init(from decoder: any Decoder) throws { // justified: Swift protocol existential, not a type-check suppression.
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

/// Owns one cache location and shares in-flight refreshes between cost scans.
actor UsageQuotaModelsDevStore {
    struct PricingSource: Equatable, Sendable {
        let catalog: ModelsDevCatalog?
        let token: String

        static let bundled = PricingSource()

        private init() {
            catalog = nil
            token = "bundled"
        }

        /// The catalog and its content identity travel together through each scan.
        init(catalog: ModelsDevCatalog) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(catalog)
            self.catalog = catalog
            token = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    private struct CacheArtifacts: Codable {
        let version: Int
        let catalog: ModelsDevCatalog
        let fetchedAt: Date
    }

    private struct LegacyMeta: Decodable {
        let version: Int
        let fetchedAt: Date
    }

    private struct FileStamp: Equatable {
        let modified: Date?
        let size: Int?

        init(url: URL) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            modified = values?.contentModificationDate
            size = values?.fileSize
        }
    }

    static let shared = UsageQuotaModelsDevStore()
    static let endpoint = URL(string: "https://models.dev/api.json")!
    static let ttl: TimeInterval = 24 * 60 * 60
    private static let artifactVersion = 2
    private static let requestTimeout: TimeInterval = 30

    private let directory: URL
    private var memo: (stamp: FileStamp, artifacts: CacheArtifacts)?
    private var refreshTask: Task<PricingSource, Never>?

    init(cacheRoot: URL? = nil) {
        let base = cacheRoot
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base
            .appendingPathComponent("com.mourato.GitMenuBar", isDirectory: true)
            .appendingPathComponent("model-pricing", isDirectory: true)
    }

    private var artifactURL: URL {
        directory.appendingPathComponent("models-dev-v\(Self.artifactVersion).json")
    }

    private func loadCached() -> CacheArtifacts? {
        let stamp = FileStamp(url: artifactURL)
        if let memo, memo.stamp == stamp {
            return memo.artifacts
        }
        if let data = try? Data(contentsOf: artifactURL),
           let decoded = try? JSONDecoder().decode(CacheArtifacts.self, from: data),
           decoded.version == Self.artifactVersion, decoded.catalog.isPlausibleRefresh()
        {
            memo = (stamp, decoded)
            return decoded
        }
        // Legacy metadata can change independently of its payload. Read both
        // until a successful refresh replaces them with the atomic artifact.
        memo = nil
        return loadLegacyCache()
    }

    /// Retain offline access to the previous two-file cache. New writes use
    /// one atomic artifact, so payload and fetch date cannot be torn apart.
    private func loadLegacyCache() -> CacheArtifacts? {
        let payloadURL = directory.appendingPathComponent("models-dev-v1.json")
        let metaURL = directory.appendingPathComponent("models-dev-v1.meta.json")
        guard let metadata = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(LegacyMeta.self, from: metadata), meta.version == 1,
              let data = try? Data(contentsOf: payloadURL),
              let catalog = try? JSONDecoder().decode(ModelsDevCatalog.self, from: data),
              catalog.isPlausibleRefresh()
        else { return nil }
        return CacheArtifacts(version: Self.artifactVersion, catalog: catalog, fetchedAt: meta.fetchedAt)
    }

    func loadOrFetch(
        now: Date = Date(),
        session: URLSession = .shared,
        fetch: (@Sendable () async throws -> Data)? = nil
    ) async -> PricingSource {
        if let refreshTask {
            return await refreshTask.value
        }
        if let cached = loadCached(), now.timeIntervalSince(cached.fetchedAt) < Self.ttl,
           let source = try? PricingSource(catalog: cached.catalog)
        {
            return source
        }
        let task = Task { await self.refresh(now: now, session: session, fetch: fetch) }
        refreshTask = task
        let source = await task.value
        refreshTask = nil
        return source
    }

    private func refresh(
        now: Date,
        session: URLSession,
        fetch: (@Sendable () async throws -> Data)?
    ) async -> PricingSource {
        let data: Data? = await {
            if let fetch {
                return try? await fetch()
            }
            var request = URLRequest(url: Self.endpoint)
            request.timeoutInterval = Self.requestTimeout
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { return nil }
            return data
        }()
        if let data,
           let catalog = try? JSONDecoder().decode(ModelsDevCatalog.self, from: data),
           catalog.isPlausibleRefresh(), let source = try? PricingSource(catalog: catalog)
        {
            let artifacts = CacheArtifacts(version: Self.artifactVersion, catalog: catalog, fetchedAt: now)
            if let encoded = try? JSONEncoder().encode(artifacts) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? encoded.write(to: artifactURL, options: .atomic)
            }
            memo = nil
            return source
        }
        if let cached = loadCached(), let source = try? PricingSource(catalog: cached.catalog) {
            return source
        }
        return .bundled
    }
}
