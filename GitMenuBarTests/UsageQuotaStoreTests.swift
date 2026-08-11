@testable import GitMenuBar
import XCTest

@MainActor
final class UsageQuotaStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var snapshotStore: UsageQuotaSnapshotStore!

    override func setUp() {
        super.setUp()
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
            providers: [provider]
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
            providers: [codexProvider, cursorProvider]
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

    func testRefreshNoOpsWhenFeatureDisabled() async {
        let provider = FakeUsageQuotaProvider(snapshot: Self.sampleSnapshot())
        let store = makeStore(provider: provider)

        store.refresh(reason: .manual)
        try? await Task.sleep(nanoseconds: 200_000_000)

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
            now: { currentDate }
        )
        store.showAIUsageQuotas = true
        await waitUntil { provider.fetchCount > 0 && !store.snapshots.isEmpty }

        store.refresh(reason: .windowPresented)
        await waitUntil { provider.fetchCount > 1 }
        let countAfterFirstPresentation = provider.fetchCount
        store.refresh(reason: .windowPresented)

        XCTAssertEqual(provider.fetchCount, countAfterFirstPresentation)
    }

    func testProviderTimeoutYieldsUnavailableWithoutHanging() async {
        let provider = HangingUsageQuotaProvider()
        let store = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider]
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

    private func makeStore(provider: FakeUsageQuotaProvider) -> UsageQuotaStore {
        UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider]
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ predicate: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for store refresh")
    }

    private static func sampleSnapshot() -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: UsageWindow(remainingPercent: 70, resetAt: Date().addingTimeInterval(3600), label: "Session"),
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

private final class FakeUsageQuotaProvider: UsageQuotaProviding, @unchecked Sendable {
    let id: UsageProviderID
    var snapshot: UsageQuotaSnapshot
    private(set) var fetchCount = 0

    init(id: UsageProviderID = .codex, snapshot: UsageQuotaSnapshot) {
        self.id = id
        self.snapshot = snapshot
    }

    // swiftlint:disable:next async_without_await
    func fetchSnapshot() async -> UsageQuotaSnapshot {
        fetchCount += 1
        return snapshot
    }
}

private struct HangingUsageQuotaProvider: UsageQuotaProviding {
    let id: UsageProviderID = .codex

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        try? await Task.sleep(nanoseconds: 60_000_000_000)
        return .unavailable(providerID: .codex, statusNote: "should not finish")
    }
}
