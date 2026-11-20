@testable import GitMenuBar
import Observation
import XCTest

@MainActor
final class UsageQuotaStoreLifecycleTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var snapshotStore: UsageQuotaSnapshotStore!
    private var testHomeDirectory: URL!
    private var openGates: [() -> Void] = []
    private var awaitCompletions: [() async -> Void] = []
    private var activeStores: [UsageQuotaStore] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        testHomeDirectory = try makeTemporaryTestDirectory(testName: "UsageQuotaStoreLifecycleTests")
        suiteName = "UsageQuotaStoreLifecycleTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated test defaults")
        }
        defaults = isolatedDefaults
        snapshotStore = UsageQuotaSnapshotStore(defaults: defaults)
        openGates.removeAll()
        awaitCompletions.removeAll()
        activeStores.removeAll()
    }

    override func tearDown() async throws {
        for gate in openGates {
            gate()
        }
        openGates.removeAll()
        for completion in awaitCompletions {
            await completion()
        }
        awaitCompletions.removeAll()
        for store in activeStores {
            store.showAIUsageQuotas = false
            await store.awaitPendingWork()
        }
        activeStores.removeAll()
        if let testHomeDirectory {
            try? FileManager.default.removeItem(at: testHomeDirectory)
        }
        testHomeDirectory = nil
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        snapshotStore = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testDisableDuringFetchPreventsLatePublication() async {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 42)
        let provider = GatedUsageQuotaProvider(id: .codex, snapshot: snapshot)
        openGates.append { provider.openGate() }
        awaitCompletions.append { await provider.awaitAllFetches() }

        let fetchStarted = expectation(description: "Fetch started")
        provider.onFetch = {
            fetchStarted.fulfill()
        }

        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await fulfillment(of: [fetchStarted], timeout: 2.0)
        XCTAssertEqual(provider.fetchCount, 1)

        store.showAIUsageQuotas = false
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.visibleSnapshots.isEmpty)
        XCTAssertNil(snapshotStore.load(providerID: .codex))

        provider.openGate()

        await store.awaitPendingWork()
        await provider.awaitAllFetches()

        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.visibleSnapshots.isEmpty)
        XCTAssertNil(snapshotStore.load(providerID: .codex))
        XCTAssertNil(store.costEstimates)
    }

    func testDisableAndReenablePermitsFreshCycleWithoutStaleOverwrite() async {
        let staleSnapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 10)
        let freshSnapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 95)
        let provider = GatedUsageQuotaProvider(id: .codex, snapshot: staleSnapshot)
        provider.setCancellationMode(.holdUntilGate, forFetch: 1)
        openGates.append { provider.openGate() }
        awaitCompletions.append { await provider.awaitAllFetches() }

        let firstFetchStarted = expectation(description: "First fetch started")
        provider.onFetch = {
            firstFetchStarted.fulfill()
        }

        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await fulfillment(of: [firstFetchStarted], timeout: 2.0)
        XCTAssertEqual(provider.fetchCount, 1)

        store.showAIUsageQuotas = false
        XCTAssertTrue(store.snapshots.isEmpty)

        provider.snapshot = freshSnapshot
        let secondFetchStarted = expectation(description: "Second fetch started")
        provider.onFetch = {
            secondFetchStarted.fulfill()
        }

        store.showAIUsageQuotas = true

        await fulfillment(of: [secondFetchStarted], timeout: 2.0)
        XCTAssertEqual(provider.fetchCount, 2)

        provider.openGate(forFetch: 2)

        await waitForObservedCondition(timeout: 2.0) {
            store.snapshots.first?.sessionWindow?.remainingPercent == 95
        }

        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.first?.sessionWindow?.remainingPercent, 95)
        XCTAssertEqual(snapshotStore.load(providerID: .codex)?.sessionWindow?.remainingPercent, 95)
        XCTAssertEqual(store.visibleSnapshots.first?.sessionWindow?.remainingPercent, 95)

        provider.openGate(forFetch: 1)
        await store.awaitPendingWork()
        await provider.awaitAllFetches()

        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.first?.sessionWindow?.remainingPercent, 95)
        XCTAssertEqual(snapshotStore.load(providerID: .codex)?.sessionWindow?.remainingPercent, 95)
        XCTAssertEqual(store.visibleSnapshots.first?.sessionWindow?.remainingPercent, 95)
    }

    func testDisableAndReenableWithSameClockYieldsCostEstimate() async throws {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 80)
        let provider = FakeImmediateQuotaProvider(snapshot: snapshot)
        let fixedNow = Date()
        try writeCodexSessionFixture(to: testHomeDirectory, now: fixedNow)

        let store = makeStore(provider: provider, now: { fixedNow })
        store.showAIUsageQuotas = true

        await waitForObservedCondition(timeout: 2.0) {
            store.costEstimates != nil
        }
        XCTAssertNotNil(store.costEstimates)

        store.showAIUsageQuotas = false
        XCTAssertNil(store.costEstimates)

        store.showAIUsageQuotas = true

        await waitForObservedCondition(timeout: 2.0) {
            store.costEstimates != nil
        }
        XCTAssertNotNil(store.costEstimates)
        XCTAssertEqual(store.costEstimates?.rows.first?.providerID, .codex)
    }

    func testStaleCycleCannotMutatePersistedCacheAfterDisable() async {
        let staleSnapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 10)
        let provider = GatedUsageQuotaProvider(id: .codex, snapshot: staleSnapshot)
        openGates.append { provider.openGate() }
        awaitCompletions.append { await provider.awaitAllFetches() }

        let fetchStarted = expectation(description: "Fetch started")
        provider.onFetch = {
            fetchStarted.fulfill()
        }

        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await fulfillment(of: [fetchStarted], timeout: 2.0)
        XCTAssertEqual(provider.fetchCount, 1)

        store.showAIUsageQuotas = false
        XCTAssertNil(snapshotStore.load(providerID: .codex))

        provider.openGate()
        await store.awaitPendingWork()
        await provider.awaitAllFetches()

        XCTAssertNil(snapshotStore.load(providerID: .codex))

        provider.onFetch = nil
        store.showAIUsageQuotas = true
        XCTAssertNil(snapshotStore.load(providerID: .codex))
        provider.openGate()
        await store.awaitPendingWork()
        await provider.awaitAllFetches()
    }

    func testReleaseOwnerDuringFetchCancelsAndDeallocates() async {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 70)
        let provider = GatedUsageQuotaProvider(id: .codex, snapshot: snapshot)
        openGates.append { provider.openGate() }
        awaitCompletions.append { await provider.awaitAllFetches() }

        let fetchStarted = expectation(description: "Fetch started")
        provider.onFetch = {
            fetchStarted.fulfill()
        }

        let fetchCancelled = expectation(description: "Fetch cancelled")
        provider.onCancel = {
            fetchCancelled.fulfill()
        }

        var store: UsageQuotaStore? = makeStore(provider: provider, track: false)
        weak var weakStore: UsageQuotaStore? = store
        store?.showAIUsageQuotas = true

        await fulfillment(of: [fetchStarted], timeout: 2.0)
        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertFalse(provider.isCancelled)
        XCTAssertNotNil(weakStore)

        let pendingWork = store?.pendingWork ?? []
        XCTAssertFalse(pendingWork.isEmpty)
        awaitCompletions.append {
            for task in pendingWork {
                await task.value
            }
        }

        store = nil

        await fulfillment(of: [fetchCancelled], timeout: 2.0)
        XCTAssertTrue(provider.isCancelled)
        XCTAssertNil(weakStore, "UsageQuotaStore should deallocate when released during an active fetch")

        provider.openGate()
        await provider.awaitAllFetches()
        for task in pendingWork {
            await task.value
        }
    }

    func testReleaseOwnerAfterReconciliationFetchStartedCancelsAndDeallocates() async {
        let codexSnapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 70)
        let claudeSnapshot = Self.sampleSnapshot(providerID: .claudeCode, remainingPercent: 80)

        let codexProvider = GatedUsageQuotaProvider(id: .codex, snapshot: codexSnapshot)
        let claudeProvider = GatedUsageQuotaProvider(id: .claudeCode, snapshot: claudeSnapshot)

        openGates.append { codexProvider.openGate() }
        openGates.append { claudeProvider.openGate() }
        awaitCompletions.append { await codexProvider.awaitAllFetches() }
        awaitCompletions.append { await claudeProvider.awaitAllFetches() }

        let initialFetchStarted = expectation(description: "Initial Codex fetch started")
        codexProvider.onFetch = {
            initialFetchStarted.fulfill()
        }

        let reconciliationFetchStarted = expectation(description: "Reconciliation Claude fetch started")
        claudeProvider.onFetch = {
            reconciliationFetchStarted.fulfill()
        }

        let reconciliationCancelled = expectation(description: "Reconciliation fetch cancelled")
        claudeProvider.onCancel = {
            reconciliationCancelled.fulfill()
        }

        defaults.set(false, forKey: AppPreferences.Keys.showClaudeCodeUsageQuota)
        defaults.set(true, forKey: AppPreferences.Keys.showCodexUsageQuota)

        var store: UsageQuotaStore? = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [codexProvider, claudeProvider],
            now: Date.init,
            pricingLoader: { .bundled },
            homeDirectory: testHomeDirectory
        )
        weak var weakStore: UsageQuotaStore? = store

        store?.showAIUsageQuotas = true

        await fulfillment(of: [initialFetchStarted], timeout: 2.0)
        XCTAssertEqual(codexProvider.fetchCount, 1)

        store?.showClaudeCodeUsageQuota = true

        codexProvider.openGate()

        await fulfillment(of: [reconciliationFetchStarted], timeout: 2.0)
        XCTAssertEqual(claudeProvider.fetchCount, 1)
        XCTAssertFalse(claudeProvider.isCancelled)
        XCTAssertNotNil(weakStore)

        let pendingWork = store?.pendingWork ?? []
        XCTAssertFalse(pendingWork.isEmpty)
        awaitCompletions.append {
            for task in pendingWork {
                await task.value
            }
        }

        store = nil

        await fulfillment(of: [reconciliationCancelled], timeout: 2.0)
        XCTAssertTrue(claudeProvider.isCancelled)
        XCTAssertNil(weakStore, "UsageQuotaStore should deallocate when released during reconciliation fetch")

        claudeProvider.openGate()
        await claudeProvider.awaitAllFetches()
        await codexProvider.awaitAllFetches()
        for task in pendingWork {
            await task.value
        }
    }

    func testCostLoaderCancellationReachesBackgroundWork() async {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 88)
        let provider = FakeImmediateQuotaProvider(snapshot: snapshot)
        let pricingLoader = GatedPricingLoader()
        openGates.append { pricingLoader.openGate() }
        awaitCompletions.append { await pricingLoader.awaitAllLoads() }

        let costScanStarted = expectation(description: "Cost scan started in background")
        pricingLoader.onLoad = {
            costScanStarted.fulfill()
        }

        let costScanCancelled = expectation(description: "Cost scan received cancellation")
        pricingLoader.onCancel = {
            costScanCancelled.fulfill()
        }

        let store = makeStore(provider: provider, pricingLoader: { await pricingLoader.load() })
        store.showAIUsageQuotas = true

        await fulfillment(of: [costScanStarted], timeout: 2.0)
        XCTAssertEqual(pricingLoader.loadCount, 1)
        XCTAssertFalse(pricingLoader.isCancelled)

        store.showAIUsageQuotas = false

        await fulfillment(of: [costScanCancelled], timeout: 2.0)
        XCTAssertTrue(pricingLoader.isCancelled)
        XCTAssertNil(store.costEstimates)

        pricingLoader.openGate()
        await pricingLoader.awaitAllLoads()
    }

    func testCompletedTasksDoNotLeakInProduction() async {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 85)
        let provider = FakeImmediateQuotaProvider(snapshot: snapshot)

        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        for _ in 0 ..< 5 {
            store.refresh(reason: .manual)
            await store.awaitPendingWork()
        }

        await store.awaitPendingWork()

        XCTAssertEqual(store.snapshots.first?.sessionWindow?.remainingPercent, 85)

        store.showAIUsageQuotas = false
        await store.awaitPendingWork()
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testOwnerCleanupWithoutSelfRetentionPitfalls() {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 50)
        let provider = FakeImmediateQuotaProvider(snapshot: snapshot)

        weak var weakStore: UsageQuotaStore?
        var retainedTimer: Timer?
        autoreleasepool {
            let store = makeStore(provider: provider, track: false)
            store.showAIUsageQuotas = true
            XCTAssertTrue(store.isRefreshTimerActive)
            weakStore = store
            retainedTimer = store.activeRefreshTimer
            XCTAssertNotNil(weakStore)
            XCTAssertNotNil(retainedTimer)
            XCTAssertTrue(retainedTimer?.isValid == true)
        }

        XCTAssertNil(weakStore, "UsageQuotaStore should deallocate without self-retention from timers or tasks")
        XCTAssertEqual(retainedTimer?.isValid, false, "Refresh timer must be invalidated when store deallocates")
    }

    private func makeStore(
        provider: any UsageQuotaProviding, // justified: Swift protocol existential, not an unchecked type escape.
        now: @escaping () -> Date = Date.init,
        pricingLoader: @escaping UsageQuotaStore.PricingLoader = { .bundled },
        track: Bool = true
    ) -> UsageQuotaStore {
        let store = UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider],
            now: now,
            pricingLoader: pricingLoader,
            homeDirectory: testHomeDirectory
        )
        if track {
            activeStores.append(store)
        }
        return store
    }

    private static func sampleSnapshot(
        providerID: UsageProviderID = .codex,
        remainingPercent: Int = 70
    ) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: providerID,
            displayName: "Codex",
            sessionWindow: UsageWindow(
                remainingPercent: remainingPercent,
                resetAt: Date().addingTimeInterval(3600),
                label: "Session"
            ),
            weeklyWindow: UsageWindow(
                remainingPercent: 90,
                resetAt: Date().addingTimeInterval(86400),
                label: "Weekly"
            ),
            isAvailable: true,
            statusNote: "sample"
        )
    }
}

@MainActor
@Observable
private final class FakeImmediateQuotaProvider: UsageQuotaProviding {
    let id: UsageProviderID
    var snapshot: UsageQuotaSnapshot

    init(id: UsageProviderID = .codex, snapshot: UsageQuotaSnapshot) {
        self.id = id
        self.snapshot = snapshot
    }

    func fetchSnapshot() -> UsageQuotaSnapshot {
        snapshot
    }
}
