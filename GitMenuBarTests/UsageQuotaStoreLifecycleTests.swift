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
    }

    override func tearDown() {
        for gate in openGates {
            gate()
        }
        openGates.removeAll()
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        snapshotStore = nil
        suiteName = nil
        super.tearDown()
    }

    func testDisableDuringFetchPreventsLatePublication() async {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 42)
        let provider = GatedUsageQuotaProvider(id: .codex, snapshot: snapshot)
        openGates.append { provider.openGate() }

        let fetchStarted = expectation(description: "Fetch started")
        provider.onFetch = {
            fetchStarted.fulfill()
        }

        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await fulfillment(of: [fetchStarted], timeout: 2.0)
        XCTAssertEqual(provider.fetchCount, 1)

        // Disable quotas while the provider fetch is still suspended at the gate.
        store.showAIUsageQuotas = false
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.visibleSnapshots.isEmpty)

        // Open gate to let the suspended provider fetch complete.
        provider.openGate()

        // Yield to allow any scheduled async actor work to drain.
        await Task.yield()

        // Verify late-arriving snapshot was discarded and not published.
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.visibleSnapshots.isEmpty)
        XCTAssertNil(store.costEstimates)
    }

    func testDisableAndReenablePermitsFreshCycleWithoutStaleOverwrite() async {
        let staleSnapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 10)
        let freshSnapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 95)
        let provider = GatedUsageQuotaProvider(id: .codex, snapshot: staleSnapshot)
        openGates.append { provider.openGate() }

        let firstFetchStarted = expectation(description: "First fetch started")
        provider.onFetch = {
            firstFetchStarted.fulfill()
        }

        let store = makeStore(provider: provider)
        store.showAIUsageQuotas = true

        await fulfillment(of: [firstFetchStarted], timeout: 2.0)
        XCTAssertEqual(provider.fetchCount, 1)

        // Disable while first fetch is suspended.
        store.showAIUsageQuotas = false
        XCTAssertTrue(store.snapshots.isEmpty)

        // Update provider with fresh snapshot and set expectation for second fetch.
        provider.snapshot = freshSnapshot
        let secondFetchStarted = expectation(description: "Second fetch started")
        provider.onFetch = {
            secondFetchStarted.fulfill()
        }

        // Re-enable: this should start a fresh cycle (generation 2).
        store.showAIUsageQuotas = true

        // First fetch was cancelled by disable, which unblocks its continuation.
        // Wait for second fetch to start.
        await fulfillment(of: [secondFetchStarted], timeout: 2.0)
        XCTAssertEqual(provider.fetchCount, 2)

        // Release gate for second fetch so fresh cycle completes.
        provider.openGate()

        await waitForObservedCondition(timeout: 2.0) {
            !store.snapshots.isEmpty
        }

        // Verify only the fresh snapshot was published.
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.first?.sessionWindow?.remainingPercent, 95)
        XCTAssertEqual(store.visibleSnapshots.first?.sessionWindow?.remainingPercent, 95)
    }

    func testCostLoaderCancellationReachesBackgroundWork() async {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 88)
        let provider = FakeImmediateQuotaProvider(snapshot: snapshot)
        let pricingLoader = GatedPricingLoader()
        openGates.append { pricingLoader.openGate() }

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

        // Wait for quota refresh to complete and cost scan to begin loading pricing in background.
        await fulfillment(of: [costScanStarted], timeout: 2.0)
        XCTAssertEqual(pricingLoader.loadCount, 1)
        XCTAssertFalse(pricingLoader.isCancelled)

        // Disabling quotas must cancel in-flight cost scan work.
        store.showAIUsageQuotas = false

        // Verify cancellation propagates to the detached background task and triggers onCancel.
        await fulfillment(of: [costScanCancelled], timeout: 2.0)
        XCTAssertTrue(pricingLoader.isCancelled)
        XCTAssertNil(store.costEstimates)
    }

    func testOwnerCleanupWithoutSelfRetentionPitfalls() {
        let snapshot = Self.sampleSnapshot(providerID: .codex, remainingPercent: 50)
        let provider = FakeImmediateQuotaProvider(snapshot: snapshot)

        weak var weakStore: UsageQuotaStore?
        autoreleasepool {
            let store = UsageQuotaStore(
                defaults: defaults,
                snapshotStore: snapshotStore,
                providers: [provider],
                now: Date.init,
                pricingLoader: { .bundled },
                homeDirectory: testHomeDirectory
            )
            store.showAIUsageQuotas = true
            weakStore = store
            XCTAssertNotNil(weakStore)
        }

        XCTAssertNil(weakStore, "UsageQuotaStore should deallocate without self-retention from timers or tasks")
    }

    // MARK: - Helpers

    private func makeStore(
        provider: any UsageQuotaProviding,
        now: @escaping () -> Date = Date.init,
        pricingLoader: @escaping UsageQuotaStore.PricingLoader = { .bundled }
    ) -> UsageQuotaStore {
        UsageQuotaStore(
            defaults: defaults,
            snapshotStore: snapshotStore,
            providers: [provider],
            now: now,
            pricingLoader: pricingLoader,
            homeDirectory: testHomeDirectory
        )
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

    // swiftlint:disable:next async_without_await
    func fetchSnapshot() async -> UsageQuotaSnapshot {
        snapshot
    }
}
