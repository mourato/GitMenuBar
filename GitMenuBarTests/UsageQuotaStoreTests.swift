@testable import GitMenuBar
import Observation
import XCTest

@MainActor
final class UsageQuotaStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var snapshotStore: UsageQuotaSnapshotStore!
    private var testHomeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testHomeDirectory = try makeTemporaryTestDirectory(testName: "UsageQuotaStoreTests")
        suiteName = "UsageQuotaStoreTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated test defaults")
        }
        defaults = isolatedDefaults
        snapshotStore = UsageQuotaSnapshotStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        snapshotStore = nil
        suiteName = nil
        super.tearDown()
    }

    func testPrimaryDisplayWindowPrefersSessionOverTighterWeekly() {
        let session = UsageWindow(remainingPercent: 98, resetAt: nil, label: "5h", durationSeconds: 5 * 3600)
        let weekly = UsageWindow(remainingPercent: 67, resetAt: nil, label: "7d", durationSeconds: 7 * 86400)
        let both = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: session,
            weeklyWindow: weekly,
            isAvailable: true
        )
        let weeklyOnly = UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: nil,
            weeklyWindow: weekly,
            isAvailable: true
        )

        XCTAssertEqual(both.primaryDisplayWindow, session)
        XCTAssertEqual(weeklyOnly.primaryDisplayWindow, weekly)
    }

    func testFeatureDisabledStartsWithEmptyVisibleSnapshots() {
        let provider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let store = makeStore(provider: provider)

        XCTAssertFalse(store.showAIUsageQuotas)
        XCTAssertTrue(store.visibleSnapshots.isEmpty)
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testEnabledProviderPublishesSuccessfulSnapshot() async {
        let provider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await waitUntil { provider.fetchCount > 0 && !store.snapshots.isEmpty }

        XCTAssertEqual(store.visibleSnapshots.count, 1)
        XCTAssertEqual(store.visibleSnapshots.first?.sessionWindow?.remainingPercent, 70)
        XCTAssertFalse(store.visibleSnapshots.first?.isStale ?? true)
    }

    func testFailureUsesCachedSnapshotMarkedStale() async {
        snapshotStore.save(Self.sampleSnapshot())
        let provider = FakeUsageQuotaProvider(snapshot: .unavailable(providerID: .codex, statusNote: "offline"))
        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await waitUntil { provider.fetchCount > 0 && store.snapshots.first?.isStale == true }

        XCTAssertEqual(store.visibleSnapshots.count, 1)
        XCTAssertTrue(store.visibleSnapshots.first?.isStale ?? false)
        XCTAssertEqual(store.visibleSnapshots.first?.statusNote, "offline")
    }

    func testCodexToggleHidesVisibleSnapshots() async {
        let provider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await waitUntil { !store.visibleSnapshots.isEmpty }

        store.showCodexUsageQuota = false

        XCTAssertTrue(store.visibleSnapshots.isEmpty)
    }

    func testCursorToggleHidesVisibleSnapshots() async {
        let provider = FakeUsageQuotaProvider(
            id: .cursor,
            snapshot: Self.cursorSampleSnapshot()
        )
        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await waitUntil { !store.visibleSnapshots.isEmpty }

        store.showCursorUsageQuota = false

        XCTAssertTrue(store.visibleSnapshots.isEmpty)
    }

    func testOpenRouterToggleHidesVisibleSnapshots() async {
        let provider = FakeUsageQuotaProvider(
            id: .openrouter,
            snapshot: Self.openRouterSampleSnapshot()
        )
        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await waitUntil { !store.visibleSnapshots.isEmpty }

        store.showOpenRouterUsageQuota = false

        XCTAssertTrue(store.visibleSnapshots.isEmpty)
    }

    func testOpenRouterWithoutSharedCredentialPublishesUnavailableSnapshot() async {
        let provider = OpenRouterUsageProvider(
            keyStore: InMemoryAIAPIKeyStore(),
            stateStore: OpenRouterUsageStateStore(defaults: defaults)
        )
        let store = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider],
            pricingLoader: { .bundled }, homeDirectory: testHomeDirectory
        )
        store.showAIUsageQuotas = true

        await waitUntil { store.snapshots.first?.providerID == .openrouter }

        XCTAssertEqual(store.snapshots.first?.statusNote, "add OpenRouter API key in Settings")
        XCTAssertTrue(store.visibleSnapshots.isEmpty)
    }

    func testCursorDisabledProviderIsSkippedDuringRefresh() async {
        let codexProvider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let cursorProvider = FakeUsageQuotaProvider(
            id: .cursor,
            snapshot: Self.cursorSampleSnapshot()
        )
        let store = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [codexProvider, cursorProvider],
            pricingLoader: { .bundled }, homeDirectory: testHomeDirectory
        )
        store.showCursorUsageQuota = false
        store.showAIUsageQuotas = true

        await waitUntil { codexProvider.fetchCount > 0 && !store.snapshots.isEmpty }

        XCTAssertGreaterThanOrEqual(codexProvider.fetchCount, 1)
        XCTAssertEqual(cursorProvider.fetchCount, 0)
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.first?.providerID, .codex)
    }

    func testEncodedSnapshotContainsNoTokenLikeKeys() {
        snapshotStore.save(Self.sampleSnapshot())

        guard let data = defaults.data(forKey: "usageQuotaSnapshot.v1.codex"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return XCTFail("Expected encoded snapshot data")
        }

        let flattenedKeys = Self.flattenKeys(json)
        XCTAssertFalse(flattenedKeys.contains(where: { $0.localizedCaseInsensitiveContains("access_token") }))
        XCTAssertFalse(flattenedKeys.contains(where: { $0.localizedCaseInsensitiveContains("refresh_token") }))
    }

    func testRefreshNoOpsWhenFeatureDisabled() {
        let provider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let store = makeStore(provider: provider)

        // refresh() returns before starting any task while the feature is disabled.
        store.refresh(reason: .manual)

        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testWindowPresentedRefreshUsesFreshSuccessfulResult() async {
        let provider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let currentDate = Date()
        let store = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider],
            now: { currentDate },
            pricingLoader: { .bundled }, homeDirectory: testHomeDirectory
        )
        store.showAIUsageQuotas = true
        await waitUntil { provider.fetchCount > 0 && !store.snapshots.isEmpty }

        provider.snapshot = Self.sampleSnapshot(remainingPercent: 55)
        store.refresh(reason: .windowPresented)
        await waitUntil { store.visibleSnapshots.first?.sessionWindow?.remainingPercent == 55 }
        let countAfterFirstPresentation = provider.fetchCount
        let unexpectedFetch = expectation(description: "fresh presentation must not fetch again")
        unexpectedFetch.isInverted = true
        provider.onFetch = { unexpectedFetch.fulfill() }
        store.refresh(reason: .windowPresented)
        await fulfillment(of: [unexpectedFetch], timeout: 0.1)

        XCTAssertEqual(provider.fetchCount, countAfterFirstPresentation)
    }

    func testProviderTimeoutYieldsUnavailableWithoutHanging() async {
        let provider = HangingUsageQuotaProvider()
        let store = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider],
            pricingLoader: { .bundled }, homeDirectory: testHomeDirectory
        )
        store.showAIUsageQuotas = true

        // Store uses an 8s provider timeout; wait slightly beyond that.
        await waitUntil(timeout: 10) {
            store.snapshots.contains { $0.statusNote == "refresh timed out" }
        }

        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.first?.statusNote, "refresh timed out")
        XCTAssertTrue(store.visibleSnapshots.isEmpty)
    }

    func testAutomaticRefreshWhileInFlightDoesNotStartSecondFetch() async {
        let provider = GatedUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let cursorProvider = GatedUsageQuotaProvider(
            id: .cursor,
            snapshot: Self.cursorSampleSnapshot()
        )
        let geminiProvider = FakeUsageQuotaProvider(
            id: .gemini,
            snapshot: Self.sampleSnapshot(providerID: .gemini)
        )
        defaults.set(false, forKey: AppPreferences.Keys.showCursorUsageQuota)
        defaults.set(false, forKey: AppPreferences.Keys.showGeminiUsageQuota)
        let store = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider, cursorProvider, geminiProvider],
            pricingLoader: { .bundled }, homeDirectory: testHomeDirectory
        )
        defer {
            provider.onFetch = nil
            cursorProvider.onFetch = nil
            store.showAIUsageQuotas = false
        }
        // Enabling the feature starts the settingsEnabled refresh, which blocks inside the fetch.
        let firstFetch = expectation(description: "in-flight fetch started")
        provider.onFetch = { firstFetch.fulfill() }
        store.showAIUsageQuotas = true
        await fulfillment(of: [firstFetch], timeout: 2)

        // Automatic requests coalesce: no second query before or after publish.
        store.refresh(reason: .timer)
        store.refresh(reason: .contentAppeared)
        store.refresh(reason: .windowPresented)
        XCTAssertEqual(provider.fetchCount, 1)

        // A provider enabled during the cycle is fetched once before that
        // same cycle publishes; the in-flight cycle is not restarted.
        let cursorFetch = expectation(description: "incremental provider fetch started")
        cursorProvider.onFetch = { cursorFetch.fulfill() }
        store.showCursorUsageQuota = true
        provider.openGate()
        await fulfillment(of: [cursorFetch], timeout: 2)

        // A second preference change during that incremental fetch is also
        // reconciled before publication.
        store.showGeminiUsageQuota = true
        cursorProvider.openGate()
        await waitUntil {
            geminiProvider.fetchCount == 1 && store.snapshots.count == 3
        }
        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(cursorProvider.fetchCount, 1)
        XCTAssertEqual(geminiProvider.fetchCount, 1)
        XCTAssertEqual(
            Set(store.snapshots.map(\.providerID)),
            Set([UsageProviderID.codex, .cursor, .gemini])
        )
    }

    func testManualRefreshWhileInFlightStillStartsNewCycle() async {
        let provider = GatedUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let store = makeStore(provider: provider)
        defer {
            provider.onFetch = nil
            store.showAIUsageQuotas = false
        }
        let firstFetch = expectation(description: "in-flight fetch started")
        provider.onFetch = { firstFetch.fulfill() }
        store.showAIUsageQuotas = true
        await fulfillment(of: [firstFetch], timeout: 2)

        // Manual remains forced: it supersedes the in-flight cycle with a new fetch.
        let manualFetch = expectation(description: "manual refresh starts a new fetch")
        provider.onFetch = { manualFetch.fulfill() }
        store.refresh(reason: .manual)
        await fulfillment(of: [manualFetch], timeout: 2)
        provider.openGate()
        await waitUntil { !store.snapshots.isEmpty }
        XCTAssertEqual(provider.fetchCount, 2)
        XCTAssertEqual(store.snapshots.first?.sessionWindow?.remainingPercent, 70)
    }

    func testManualRefreshCostScanRespectsIntervalBoundary() async {
        var currentDate = Date()
        let provider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let pricingLoader = CountingPricingLoader()
        let firstScan = expectation(description: "first cost scan loads pricing")
        pricingLoader.onLoad = { firstScan.fulfill() }
        let store = makeStore(
            provider: provider,
            pricingLoader: { pricingLoader.load() },
            now: { currentDate }
        )
        store.showAIUsageQuotas = true
        await fulfillment(of: [firstScan], timeout: 2)
        await waitUntil { store.visibleSnapshots.first?.sessionWindow?.remainingPercent == 70 }

        // Inside the 600 s interval: manual force-refreshes quota counts only.
        provider.snapshot = Self.sampleSnapshot(remainingPercent: 55)
        store.refresh(reason: .manual)
        await waitUntil {
            provider.fetchCount == 2
                && store.visibleSnapshots.first?.sessionWindow?.remainingPercent == 55
        }
        let noRescan = expectation(description: "manual refresh must not load pricing inside the interval")
        noRescan.isInverted = true
        pricingLoader.onLoad = { noRescan.fulfill() }
        await fulfillment(of: [noRescan], timeout: 0.1)
        XCTAssertEqual(pricingLoader.loadCount, 1)
        // After the interval passes, manual prices again while still fetching quotas.
        let rescan = expectation(description: "post-interval manual refresh loads pricing again")
        pricingLoader.onLoad = { rescan.fulfill() }
        currentDate = currentDate.addingTimeInterval(601)
        store.refresh(reason: .manual)
        await fulfillment(of: [rescan], timeout: 2)
        XCTAssertEqual(provider.fetchCount, 3)
        XCTAssertEqual(pricingLoader.loadCount, 2)
    }

    func testCostScanPublishesAfterManualRefreshDuringPricingLoad() async throws {
        let currentDate = Date()
        try writeCodexSessionFixture(to: testHomeDirectory, now: currentDate)
        let provider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let pricingLoader = GatedPricingLoader()
        let scanStarted = expectation(description: "cost scan started")
        pricingLoader.onLoad = { scanStarted.fulfill() }
        let store = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider],
            now: { currentDate },
            pricingLoader: { await pricingLoader.load() }, homeDirectory: testHomeDirectory
        )

        store.showAIUsageQuotas = true
        await fulfillment(of: [scanStarted], timeout: 2)
        XCTAssertEqual(pricingLoader.loadCount, 1)

        store.refresh(reason: .manual)
        await waitUntil {
            provider.fetchCount == 2
                && store.visibleSnapshots.first?.sessionWindow?.remainingPercent == 70
        }

        pricingLoader.openGate()
        await waitUntil { store.costEstimates?.rows.count == 1 }

        XCTAssertEqual(pricingLoader.loadCount, 1)
        XCTAssertEqual(store.costEstimates?.rows.first?.providerID, .codex)
    }

    private func makeStore(
        provider: some UsageQuotaProviding,
        pricingLoader: @escaping UsageQuotaStore.PricingLoader = { .bundled },
        now: @escaping () -> Date = Date.init
    ) -> UsageQuotaStore {
        UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider],
            now: now,
            pricingLoader: pricingLoader, homeDirectory: testHomeDirectory
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        await waitForObservedCondition(timeout: timeout, predicate)
    }

    private static func sampleSnapshot(
        providerID: UsageProviderID = .codex,
        remainingPercent: Int = 70
    ) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: providerID,
            displayName: providerID == .gemini ? "Gemini" : "Codex",
            sessionWindow: UsageWindow(remainingPercent: remainingPercent, resetAt: Date().addingTimeInterval(3600), label: "Session"),
            weeklyWindow: UsageWindow(remainingPercent: 90, resetAt: Date().addingTimeInterval(86400), label: "Weekly"),
            isAvailable: true,
            statusNote: "chatgpt usage api"
        )
    }

    private static func cursorSampleSnapshot() -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: .cursor,
            displayName: "Cursor",
            sessionWindow: UsageWindow(remainingPercent: 55, resetAt: Date().addingTimeInterval(7200), label: "Plan"),
            weeklyWindow: nil,
            creditValueText: "$12.00 left",
            isAvailable: true,
            statusNote: "cursor usage-summary api"
        )
    }

    private static func openRouterSampleSnapshot() -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: .openrouter,
            displayName: "OpenRouter",
            sessionWindow: UsageWindow(remainingPercent: 60, resetAt: nil, label: "Credits"),
            weeklyWindow: nil,
            creditValueText: "$6.00 left",
            isAvailable: true,
            statusNote: "openrouter credits api"
        )
    }

    private static func flattenKeys(_ value: Any, prefix: String = "") -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, nested in
                flattenKeys(nested, prefix: prefix + key + ".")
            } + dictionary.keys.map { prefix + $0 }
        }
        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, nested in
                flattenKeys(nested, prefix: prefix + "[\(index)].")
            }
        }
        return prefix.isEmpty ? [] : [prefix]
    }
}

@MainActor
@Observable
private final class FakeUsageQuotaProvider: UsageQuotaProviding {
    let id: UsageProviderID
    var snapshot: UsageQuotaSnapshot
    private(set) var fetchCount = 0
    var onFetch: (() -> Void)?

    init(id: UsageProviderID = .codex, snapshot: UsageQuotaSnapshot) {
        self.id = id
        self.snapshot = snapshot
    }

    // swiftlint:disable:next async_without_await
    func fetchSnapshot() async -> UsageQuotaSnapshot {
        fetchCount += 1
        onFetch?()
        return snapshot
    }
}

private struct HangingUsageQuotaProvider: UsageQuotaProviding {
    let id: UsageProviderID = .codex
    /// Never yields; the store's timeout group cancels the fetch, which ends the loop.
    private let neverYields = AsyncStream<Void> { _ in }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        for await _ in neverYields {}
        return .unavailable(providerID: .codex, statusNote: "should not finish")
    }
}
