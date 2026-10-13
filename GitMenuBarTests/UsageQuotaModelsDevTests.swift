@testable import GitMenuBar
import XCTest

final class UsageQuotaModelsDevTests: XCTestCase {
    private actor FetchCounter {
        private(set) var count = 0
        let payload: Data

        init(payload: Data) {
            self.payload = payload
        }

        func fetch() -> Data {
            count += 1
            return payload
        }
    }

    private let catalogJSON = """
    {
      "openai": {
        "id": "openai",
        "name": "OpenAI",
        "models": {
          "gpt-6.1-sol": {
            "id": "gpt-6.1-sol",
            "name": "GPT-6.1 Sol",
            "cost": {
              "input": 2,
              "output": 10,
              "cache_read": 0.1,
              "cache_write": 2.5,
              "tiers": [{ "input": 4, "output": 15, "cache_read": 0.2, "cache_write": 5,
                "tier": { "type": "context", "size": 272000 } }],
              "context_over_200k": { "input": 4, "output": 15, "cache_read": 0.2, "cache_write": 5 }
            }
          },
          "gpt-5.6-luna": {
            "id": "gpt-5.6-luna",
            "cost": { "input": 99, "output": 99 }
          }
        }
      },
      "anthropic": {
        "id": "anthropic",
        "name": "Anthropic",
        "models": {
          "claude-test-1": {
            "id": "claude-test-1",
            "cost": { "input": 3, "output": 15, "cache_read": 0.3, "cache_write": 3.75 }
          },
          "claude-new-5-20261001@default": {
            "id": "claude-new-5-20261001@default",
            "cost": { "input": 1, "output": 5 }
          }
        }
      }
    }
    """

    private func makeCatalog(_ json: String? = nil) throws -> ModelsDevCatalog {
        try JSONDecoder().decode(
            ModelsDevCatalog.self,
            from: Data((json ?? catalogJSON).utf8)
        )
    }

    func testCatalogDecodesFlatProviderMapAndResolvesModels() throws {
        let catalog = try makeCatalog()
        XCTAssertTrue(catalog.isPlausibleRefresh())

        let model = try XCTUnwrap(catalog.model(providerID: "openai", rawModelID: "gpt-6.1-sol"))
        XCTAssertEqual(model.cost?.input, 2)
        XCTAssertEqual(model.cost?.contextOver200K?.output, 15)

        // Provider-prefixed IDs resolve through the candidate list.
        let prefixed = try XCTUnwrap(catalog.model(providerID: "openai", rawModelID: "openai/gpt-6.1-sol"))
        XCTAssertEqual(prefixed.id, "gpt-6.1-sol")

        XCTAssertNil(catalog.model(providerID: "openai", rawModelID: "missing-model"))
    }

    func testClaudeDatedSnapshotResolvesThroughDefaultAlias() throws {
        let catalog = try makeCatalog()
        let model = try XCTUnwrap(catalog.model(providerID: "anthropic", rawModelID: "claude-new-5-20261001"))
        XCTAssertEqual(model.id, "claude-new-5-20261001@default")
    }

    func testImplausibleCatalogFailsPlausibility() throws {
        let catalog = try makeCatalog(#"{"openai": {"id": "openai", "models": {}}}"#)
        XCTAssertFalse(catalog.isPlausibleRefresh())
    }

    func testCodexCostPrefersCatalogOverBundledTable() throws {
        // Catalog prices gpt-5.6-luna at $99/M in and out; the bundled table
        // says input 2e-7 / output 1.2e-6. The catalog must win.
        let catalog = try makeCatalog()
        let cost = try XCTUnwrap(UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-5.6-luna",
            inputTokens: 1000,
            cachedInputTokens: 0,
            outputTokens: 100,
            catalog: catalog
        ))
        let expected = Double(1000) * 99e-6 + Double(100) * 99e-6
        XCTAssertEqual(cost, expected, accuracy: 1e-9)
    }

    func testCodexCostAppliesCatalogLongContextRates() throws {
        // The explicit tier threshold takes precedence over the legacy 200K block.
        let catalog = try makeCatalog()
        let cost = try XCTUnwrap(UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-6.1-sol",
            inputTokens: 272_001,
            cachedInputTokens: 0,
            outputTokens: 1000,
            catalog: catalog
        ))
        let expected = Double(272_001) * 4e-6 + Double(1000) * 15e-6
        XCTAssertEqual(cost, expected, accuracy: 1e-9)
        for input in [200_001, 250_000, 272_000] {
            let belowThreshold = try XCTUnwrap(UsageQuotaAPIPricing.codexCostUSD(
                model: "gpt-6.1-sol",
                inputTokens: input,
                cachedInputTokens: 0,
                outputTokens: 1000,
                catalog: catalog
            ))
            XCTAssertEqual(belowThreshold, Double(input) * 2e-6 + 0.01, accuracy: 1e-9)
        }
    }

    func testCodexCostFallsBackToBundledWhenCatalogMisses() throws {
        let catalog = try makeCatalog()
        let withCatalog = try XCTUnwrap(UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 10,
            catalog: catalog
        ))
        let bundled = try XCTUnwrap(UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-5.6-terra",
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 10
        ))
        XCTAssertEqual(withCatalog, bundled, accuracy: 1e-12)
    }

    func testClaudeCostUsesCatalogRates() throws {
        // claude-test-1: input $3/M, output $15/M, read $0.3/M, write $3.75/M.
        let catalog = try makeCatalog()
        let cost = try XCTUnwrap(UsageQuotaAPIPricing.claudeCostUSD(
            model: "claude-test-1",
            inputTokens: 1000,
            cacheReadInputTokens: 200,
            cacheCreationInputTokens: 100,
            outputTokens: 50,
            catalog: catalog
        ))
        let expected = Double(1000) * 3e-6 + Double(200) * 0.3e-6
            + Double(100) * 3.75e-6 + Double(50) * 15e-6
        XCTAssertEqual(cost, expected, accuracy: 1e-12)
    }

    func testStorePersistsFetchAndServesStaleOnFailure() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevStore")
        let payload = Data(catalogJSON.utf8)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let first = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(
            now: fetchedAt,
            fetch: { payload }
        )
        XCTAssertNotNil(first.catalog)
        XCTAssertNotEqual(first.token, UsageQuotaModelsDevStore.PricingSource.bundled.token)

        // Beyond the TTL a failing fetch must keep serving the cached catalog.

        let stale = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(
            now: fetchedAt.addingTimeInterval(UsageQuotaModelsDevStore.ttl + 60),
            fetch: { throw URLError(.notConnectedToInternet) }
        )
        XCTAssertEqual(stale.catalog, first.catalog)
    }

    func testStoreRejectsImplausibleCatalogAndKeepsGoodCache() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevImplausible")
        let payload = Data(catalogJSON.utf8)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let first = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(
            now: fetchedAt,
            fetch: { payload }
        )
        XCTAssertNotNil(first.catalog)

        let rejected = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(
            now: fetchedAt.addingTimeInterval(UsageQuotaModelsDevStore.ttl + 60),
            fetch: { Data("{}".utf8) }
        )
        XCTAssertEqual(rejected.catalog, first.catalog)
    }

    func testStoreWithoutCacheOrNetworkIsBundled() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevOffline")
        let source = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(
            now: Date(),
            fetch: { throw URLError(.notConnectedToInternet) }
        )
        XCTAssertEqual(source, .bundled)
    }

    func testFreshCacheSurvivesRelaunchWithoutFetching() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevFresh")
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = Data(catalogJSON.utf8)
        let first = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(now: fetchedAt, fetch: { payload })
        let reloaded = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(
            now: fetchedAt.addingTimeInterval(60),
            fetch: {
                XCTFail("A fresh persisted cache must not fetch")
                throw URLError(.notConnectedToInternet)
            }
        )
        XCTAssertEqual(reloaded, first)
        XCTAssertEqual(reloaded.catalog?.model(providerID: "openai", rawModelID: "gpt-6.1-sol")?.cost?.input, 2)
    }

    func testContentIdentityDistinguishesCatalogsFetchedInSameSecond() async throws {
        let firstRoot = try makeTemporaryTestDirectory(testName: "ModelsDevIdentityA")
        let secondRoot = try makeTemporaryTestDirectory(testName: "ModelsDevIdentityB")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let firstPayload = Data(catalogJSON.utf8)
        let secondPayload = Data(catalogJSON.replacingOccurrences(of: "\"input\": 2,", with: "\"input\": 8,").utf8)
        let first = await UsageQuotaModelsDevStore(cacheRoot: firstRoot).loadOrFetch(now: now, fetch: { firstPayload })
        let second = await UsageQuotaModelsDevStore(cacheRoot: secondRoot).loadOrFetch(now: now, fetch: { secondPayload })
        XCTAssertNotEqual(first.token, second.token)
        XCTAssertEqual(second.catalog?.model(providerID: "openai", rawModelID: "gpt-6.1-sol")?.cost?.input, 8)
        let repeated = await UsageQuotaModelsDevStore(cacheRoot: firstRoot).loadOrFetch(
            now: now.addingTimeInterval(UsageQuotaModelsDevStore.ttl + 1), fetch: { firstPayload }
        )
        XCTAssertEqual(repeated.token, first.token)
    }

    func testRejectsNegativePricesAndUsesBundledFallback() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevNegative")
        let json = #"{"openai":{"models":{"gpt-6.1-sol":{"id":"gpt-6.1-sol","cost":{"input":-2,"output":10}}}},"anthropic":{"models":{"claude-test":{"id":"claude-test","cost":{"input":-3,"output":15}}}}}"#
        let catalog = try makeCatalog(json)
        XCTAssertFalse(catalog.isPlausibleRefresh())
        XCTAssertEqual(UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-6.1-sol", inputTokens: 1000, cachedInputTokens: 0, outputTokens: 100, catalog: catalog
        ) ?? -1, 0.003, accuracy: 1e-12)
        let source = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(fetch: { Data(json.utf8) })
        XCTAssertEqual(source, .bundled)
    }

    func testReadsLegacyCacheAndObservesChangedMetadata() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevLegacy")
        let directory = root.appendingPathComponent("com.mourato.GitMenuBar/model-pricing")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(catalogJSON.utf8).write(to: directory.appendingPathComponent("models-dev-v1.json"))
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let meta = directory.appendingPathComponent("models-dev-v1.meta.json")
        try Data(#"{"version":1,"fetchedAt":10000000}"#.utf8).write(to: meta)
        let store = UsageQuotaModelsDevStore(cacheRoot: root)
        let first = await store.loadOrFetch(now: now, fetch: {
            XCTFail("Fresh legacy data must stay usable offline")
            throw URLError(.notConnectedToInternet)
        })
        XCTAssertEqual(first.catalog?.model(providerID: "openai", rawModelID: "gpt-6.1-sol")?.cost?.input, 2)
        try Data(#"{"version":1,"fetchedAt":0}"#.utf8).write(to: meta)
        let newPayload = Data(catalogJSON.replacingOccurrences(of: "\"input\": 2,", with: "\"input\": 8,").utf8)
        let refreshed = await store.loadOrFetch(now: now, fetch: { newPayload })
        XCTAssertEqual(refreshed.catalog?.model(providerID: "openai", rawModelID: "gpt-6.1-sol")?.cost?.input, 8)
        XCTAssertNotEqual(refreshed.token, first.token)
    }

    func testConcurrentRefreshesShareOneCatalogAndPersistItTogether() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevConcurrent")
        let store = UsageQuotaModelsDevStore(cacheRoot: root)
        let counter = FetchCounter(payload: Data(catalogJSON.utf8))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sources = await withTaskGroup(of: UsageQuotaModelsDevStore.PricingSource.self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    await store.loadOrFetch(now: now, fetch: { await counter.fetch() })
                }
            }
            var sources: [UsageQuotaModelsDevStore.PricingSource] = []
            for await source in group {
                sources.append(source)
            }
            return sources
        }
        let fetchCount = await counter.count
        XCTAssertEqual(fetchCount, 1)
        let first = try XCTUnwrap(sources.first)
        XCTAssertTrue(sources.allSatisfy { $0 == first })
        let reloaded = await UsageQuotaModelsDevStore(cacheRoot: root).loadOrFetch(now: now, fetch: {
            XCTFail("Concurrent refresh must persist one fresh artifact")
            throw URLError(.notConnectedToInternet)
        })
        XCTAssertEqual(reloaded, first)
    }
}
