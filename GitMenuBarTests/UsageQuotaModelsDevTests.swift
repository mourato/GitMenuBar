@testable import GitMenuBar
import XCTest

final class UsageQuotaModelsDevTests: XCTestCase {
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

    override func setUp() {
        super.setUp()
        UsageQuotaModelsDevStore.resetMemoForTesting()
    }

    override func tearDown() {
        UsageQuotaModelsDevStore.resetMemoForTesting()
        super.tearDown()
    }

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
        // gpt-6.1-sol above the catalog's 200K context threshold bills the
        // context_over_200k rates for input and output.
        let catalog = try makeCatalog()
        let cost = try XCTUnwrap(UsageQuotaAPIPricing.codexCostUSD(
            model: "gpt-6.1-sol",
            inputTokens: 250_000,
            cachedInputTokens: 0,
            outputTokens: 1000,
            catalog: catalog
        ))
        let expected = Double(250_000) * 4e-6 + Double(1000) * 15e-6
        XCTAssertEqual(cost, expected, accuracy: 1e-9)
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

        let first = await UsageQuotaModelsDevStore.loadOrFetch(
            now: fetchedAt,
            cacheRoot: root,
            fetch: { payload }
        )
        XCTAssertNotNil(first.catalog)
        XCTAssertNotEqual(first.token, UsageQuotaModelsDevStore.PricingSource.bundled.token)

        // Beyond the TTL a failing fetch must keep serving the cached catalog.
        UsageQuotaModelsDevStore.resetMemoForTesting()
        let stale = await UsageQuotaModelsDevStore.loadOrFetch(
            now: fetchedAt.addingTimeInterval(UsageQuotaModelsDevStore.ttl + 60),
            cacheRoot: root,
            fetch: { throw URLError(.notConnectedToInternet) }
        )
        XCTAssertEqual(stale.catalog, first.catalog)
    }

    func testStoreRejectsImplausibleCatalogAndKeepsGoodCache() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevImplausible")
        let payload = Data(catalogJSON.utf8)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let first = await UsageQuotaModelsDevStore.loadOrFetch(
            now: fetchedAt,
            cacheRoot: root,
            fetch: { payload }
        )
        XCTAssertNotNil(first.catalog)

        UsageQuotaModelsDevStore.resetMemoForTesting()
        let rejected = await UsageQuotaModelsDevStore.loadOrFetch(
            now: fetchedAt.addingTimeInterval(UsageQuotaModelsDevStore.ttl + 60),
            cacheRoot: root,
            fetch: { Data("{}".utf8) }
        )
        XCTAssertEqual(rejected.catalog, first.catalog)
    }

    func testStoreWithoutCacheOrNetworkIsBundled() async throws {
        let root = try makeTemporaryTestDirectory(testName: "ModelsDevOffline")
        let source = await UsageQuotaModelsDevStore.loadOrFetch(
            now: Date(),
            cacheRoot: root,
            fetch: { throw URLError(.notConnectedToInternet) }
        )
        XCTAssertEqual(source, .bundled)
    }
}
