import Combine
import Foundation
import Observation

@MainActor
@Observable
final class UsageQuotaStore {
    enum RefreshReason: String {
        case windowPresented
        case timer
        case manual
        case settingsEnabled
        case contentAppeared
    }

    private enum Constants {
        static let refreshInterval: TimeInterval = 120
        static let providerTimeout: TimeInterval = 8
        static let costScanInterval: TimeInterval = 600
    }

    private(set) var snapshots: [UsageQuotaSnapshot] = []
    /// Current-month API-equivalent spend estimate; nil until the first refresh scans local sessions.
    private(set) var costEstimates: UsageQuotaCostEstimate?
    /// Reset credits with a redemption in flight; their menu items stay disabled until the attempt settles.
    private(set) var redeemingResetCreditIDs: Set<String> = []
    private func updatePreference(_ key: String, value: Bool, oldValue: Bool) {
        guard value != oldValue else { return }
        defaults.set(value, forKey: key)
        handlePreferenceChange()
    }

    var showAIUsageQuotas: Bool {
        didSet { updatePreference(AppPreferences.Keys.showAIUsageQuotas, value: showAIUsageQuotas, oldValue: oldValue) }
    }

    var showClaudeCodeUsageQuota: Bool {
        didSet { updatePreference(AppPreferences.Keys.showClaudeCodeUsageQuota, value: showClaudeCodeUsageQuota, oldValue: oldValue) }
    }

    var showCodexUsageQuota: Bool {
        didSet { updatePreference(AppPreferences.Keys.showCodexUsageQuota, value: showCodexUsageQuota, oldValue: oldValue) }
    }

    var showCursorUsageQuota: Bool {
        didSet { updatePreference(AppPreferences.Keys.showCursorUsageQuota, value: showCursorUsageQuota, oldValue: oldValue) }
    }

    var showOpenRouterUsageQuota: Bool {
        didSet { updatePreference(AppPreferences.Keys.showOpenRouterUsageQuota, value: showOpenRouterUsageQuota, oldValue: oldValue) }
    }

    var showGeminiUsageQuota: Bool {
        didSet { updatePreference(AppPreferences.Keys.showGeminiUsageQuota, value: showGeminiUsageQuota, oldValue: oldValue) }
    }

    var showAntigravityUsageQuota: Bool {
        didSet { updatePreference(AppPreferences.Keys.showAntigravityUsageQuota, value: showAntigravityUsageQuota, oldValue: oldValue) }
    }

    /// Resolves the pricing source for a cost scan. Injectable so tests never
    /// touch the network; production fetches and caches the models.dev catalog.
    typealias PricingLoader = @Sendable () async -> UsageQuotaModelsDevStore.PricingSource

    private let defaults: UserDefaults
    private let snapshotStore: UsageQuotaSnapshotStore
    private let providers: [any UsageQuotaProviding]
    private let codexProvider: CodexUsageProvider
    private let now: () -> Date
    private let pricingLoader: PricingLoader
    private let homeDirectory: URL
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var isRefreshInFlight = false
    @ObservationIgnored private var lastPresentationRefreshAt: Date?
    @ObservationIgnored private var lastCostScanAt: Date?
    @ObservationIgnored private var costScanGeneration = 0
    @ObservationIgnored private var costScanTask: Task<Void, Never>?
    @ObservationIgnored private var costScanWorkerTask: Task<UsageQuotaCostEstimate, Never>?
    @ObservationIgnored private var pendingTasks: [UInt64: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTaskID: UInt64 = 0

    isolated deinit {
        refreshTimer?.invalidate()
        refreshTask?.cancel()
        costScanTask?.cancel()
        costScanWorkerTask?.cancel()
    }

    var isRefreshTimerActive: Bool {
        refreshTimer?.isValid == true
    }

    var activeRefreshTimer: Timer? {
        refreshTimer
    }

    private func trackPendingTask(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = nextTaskID
        nextTaskID &+= 1
        let task = Task { [weak self] in
            defer {
                self?.pendingTasks.removeValue(forKey: id)
            }
            await operation()
        }
        pendingTasks[id] = task
        return task
    }

    func awaitPendingWork() async {
        while !pendingTasks.isEmpty {
            let tasks = Array(pendingTasks.values)
            for task in tasks {
                _ = await task.value
            }
        }
    }

    init(
        defaults: UserDefaults = .standard,
        snapshotStore: UsageQuotaSnapshotStore = UsageQuotaSnapshotStore(),
        providers: [any UsageQuotaProviding] = [
            ClaudeCodeUsageProvider(),
            CodexUsageProvider(),
            CursorUsageProvider(),
            OpenRouterUsageProvider(),
            GeminiUsageProvider(),
            AntigravityUsageProvider()
        ],
        codexProvider: CodexUsageProvider = CodexUsageProvider(),
        now: @escaping () -> Date = Date.init,
        pricingLoader: @escaping PricingLoader = { await UsageQuotaModelsDevStore.shared.loadOrFetch() },
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.defaults = defaults
        self.snapshotStore = snapshotStore
        self.providers = providers
        self.codexProvider = codexProvider
        self.now = now
        self.pricingLoader = pricingLoader
        self.homeDirectory = homeDirectory
        showAIUsageQuotas = defaults.object(forKey: AppPreferences.Keys.showAIUsageQuotas) as? Bool ?? false
        showClaudeCodeUsageQuota = defaults.object(forKey: AppPreferences.Keys.showClaudeCodeUsageQuota) as? Bool ?? true
        showCodexUsageQuota = defaults.object(forKey: AppPreferences.Keys.showCodexUsageQuota) as? Bool ?? true
        showCursorUsageQuota = defaults.object(forKey: AppPreferences.Keys.showCursorUsageQuota) as? Bool ?? true
        showOpenRouterUsageQuota = defaults.object(forKey: AppPreferences.Keys.showOpenRouterUsageQuota) as? Bool ?? true
        showGeminiUsageQuota = defaults.object(forKey: AppPreferences.Keys.showGeminiUsageQuota) as? Bool ?? true
        showAntigravityUsageQuota = defaults.object(forKey: AppPreferences.Keys.showAntigravityUsageQuota) as? Bool ?? true
        handlePreferenceChange(loadCachedOnly: true)
    }

    var visibleSnapshots: [UsageQuotaSnapshot] {
        guard showAIUsageQuotas else { return [] }
        return snapshots.filter { snapshot in
            isProviderEnabled(snapshot.providerID) && snapshot.isAvailable
        }
    }

    private func shouldThrottleRefresh(reason: RefreshReason) -> Bool {
        switch reason {
        case .manual:
            false
        case .windowPresented:
            isRefreshInFlight || (lastPresentationRefreshAt.map { now().timeIntervalSince($0) < Constants.refreshInterval } ?? false)
        case .timer, .settingsEnabled, .contentAppeared:
            isRefreshInFlight
        }
    }

    func refresh(reason: RefreshReason = .manual) {
        guard showAIUsageQuotas, !shouldThrottleRefresh(reason: reason) else { return }

        // Only manual refreshes reach here with non-nil work in flight.
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshInFlight = true

        let activeProviders = enabledProviders()
        guard !activeProviders.isEmpty else {
            snapshots = []
            finishRefresh(reason: reason, generation: generation)
            return
        }

        refreshTask = trackPendingTask { [weak self] in
            await Self.runRefreshLoop(
                initialProviders: activeProviders,
                reconcile: { [weak self] newlyFetched, accumulated, fetchedIDs in
                    self?.reconcileFetchStep(
                        newlyFetched: newlyFetched,
                        accumulated: accumulated,
                        fetchedProviderIDs: fetchedIDs,
                        generation: generation
                    )
                },
                finalize: { [weak self] allSnapshots in
                    self?.finalizeRefreshSynchronous(snapshots: allSnapshots, reason: reason, generation: generation)
                }
            )
        }
    }

    private static func runRefreshLoop(
        initialProviders: [any UsageQuotaProviding],
        reconcile: ([UsageQuotaSnapshot], [UsageQuotaSnapshot], Set<UsageProviderID>) -> ReconciliationStepAction?,
        finalize: ([UsageQuotaSnapshot]) -> Void
    ) async {
        let trace = GitPerformanceTrace.begin("usage.quota.refresh")
        defer { GitPerformanceTrace.end("usage.quota.refresh", id: trace) }

        var providersToFetch = initialProviders
        var accumulatedSnapshots: [UsageQuotaSnapshot] = []
        var fetchedProviderIDs = Set<UsageProviderID>()

        while !providersToFetch.isEmpty {
            fetchedProviderIDs.formUnion(providersToFetch.map(\.id))
            let newlyFetched = await fetchSnapshots(for: providersToFetch)

            guard let action = reconcile(newlyFetched, accumulatedSnapshots, fetchedProviderIDs) else {
                return
            }

            switch action {
            case let .fetchMore(nextProviders, updatedAccumulated):
                providersToFetch = nextProviders
                accumulatedSnapshots = updatedAccumulated
            case let .finalize(allSnapshots):
                finalize(allSnapshots)
                return
            }
        }
    }

    /// Spends one Codex reset credit and refreshes usage so counts match the server.
    /// Returns nil without a request when that credit is already being redeemed.
    func redeemCodexResetCredit(_ credit: UsageQuotaResetCredit) async -> CodexResetRedeemOutcome? {
        guard !redeemingResetCreditIDs.contains(credit.id) else { return nil }
        redeemingResetCreditIDs.insert(credit.id)
        defer { redeemingResetCreditIDs.remove(credit.id) }

        let outcome = await codexProvider.redeemResetCredit(id: credit.id)
        refresh(reason: .manual)
        return outcome
    }

    private func handlePreferenceChange(loadCachedOnly: Bool = false) {
        if showAIUsageQuotas {
            loadCachedSnapshots()
            configureRefreshTimer()
            if !loadCachedOnly {
                refresh(reason: .settingsEnabled)
            }
        } else {
            invalidateRefreshTimer()
            cancelRefresh()
            cancelCostScan()
            lastCostScanAt = nil
            lastPresentationRefreshAt = nil
            snapshots = []
            costEstimates = nil
        }
    }

    private func cancelRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshInFlight = false
    }

    private func cancelCostScan() {
        costScanGeneration += 1
        costScanWorkerTask?.cancel()
        costScanTask?.cancel()
    }

    private func loadCachedSnapshots() {
        snapshots = enabledProviders().compactMap { provider in
            snapshotStore.load(providerID: provider.id)
        }
    }

    private func configureRefreshTimer() {
        invalidateRefreshTimer()
        guard showAIUsageQuotas else { return }

        let timer = Timer(timeInterval: Constants.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reason: .timer)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func invalidateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func enabledProviders() -> [any UsageQuotaProviding] {
        providers.filter { isProviderEnabled($0.id) }
    }

    func isProviderEnabled(_ providerID: UsageProviderID) -> Bool {
        switch providerID {
        case .claudeCode: showClaudeCodeUsageQuota
        case .codex: showCodexUsageQuota
        case .cursor: showCursorUsageQuota
        case .openrouter: showOpenRouterUsageQuota
        case .gemini: showGeminiUsageQuota
        case .antigravity: showAntigravityUsageQuota
        }
    }

    func setProviderEnabled(_ isEnabled: Bool, for providerID: UsageProviderID) {
        switch providerID {
        case .claudeCode: showClaudeCodeUsageQuota = isEnabled
        case .codex: showCodexUsageQuota = isEnabled
        case .cursor: showCursorUsageQuota = isEnabled
        case .openrouter: showOpenRouterUsageQuota = isEnabled
        case .gemini: showGeminiUsageQuota = isEnabled
        case .antigravity: showAntigravityUsageQuota = isEnabled
        }
    }

    private enum ReconciliationStepAction {
        case fetchMore([any UsageQuotaProviding], [UsageQuotaSnapshot])
        case finalize([UsageQuotaSnapshot])
    }

    private func reconcileFetchStep(
        newlyFetched: [UsageQuotaSnapshot],
        accumulated: [UsageQuotaSnapshot],
        fetchedProviderIDs: Set<UsageProviderID>,
        generation: Int
    ) -> ReconciliationStepAction? {
        guard showAIUsageQuotas, generation == refreshGeneration else {
            return nil
        }

        let totalAccumulated = accumulated + newlyFetched
        let currentProviders = enabledProviders()
        let newlyEnabledProviders = currentProviders.filter { !fetchedProviderIDs.contains($0.id) }

        if !newlyEnabledProviders.isEmpty {
            return .fetchMore(newlyEnabledProviders, totalAccumulated)
        } else {
            return .finalize(totalAccumulated)
        }
    }

    private func finalizeRefreshSynchronous(
        snapshots rawSnapshots: [UsageQuotaSnapshot],
        reason: RefreshReason,
        generation: Int
    ) {
        guard showAIUsageQuotas, generation == refreshGeneration else {
            finishRefresh(reason: reason, generation: generation)
            return
        }

        let currentProviderIDs = Set(enabledProviders().map(\.id))
        var merged = rawSnapshots
        merged.removeAll { !currentProviderIDs.contains($0.providerID) }

        var resolved = merged.map { resolveSnapshot($0) }
        resolved.sort { $0.providerID.rawValue < $1.providerID.rawValue }

        guard showAIUsageQuotas, generation == refreshGeneration else { return }
        for snapshot in resolved where snapshot.isAvailable {
            snapshotStore.save(snapshot)
        }
        snapshots = resolved
        finishRefresh(reason: reason, generation: generation)
        refreshCostEstimates()
    }

    private static func fetchSnapshots(for providers: [any UsageQuotaProviding]) async -> [UsageQuotaSnapshot] {
        await withTaskGroup(of: UsageQuotaSnapshot.self, returning: [UsageQuotaSnapshot].self) { group in
            for provider in providers {
                group.addTask {
                    await Self.fetchWithTimeout(provider: provider, timeout: Constants.providerTimeout)
                }
            }

            var results: [UsageQuotaSnapshot] = []
            for await snapshot in group {
                results.append(snapshot)
            }
            return results
        }
    }

    /// Monthly spend estimate rides along without holding provider-refresh timing hostage.
    /// The scan gate is time-based for every reason: while the last scan is still
    /// fresh, a manual quota refresh only re-queries providers instead of also
    /// enumerating the JSONL sessions again.
    private func refreshCostEstimates() {
        guard showAIUsageQuotas else { return }
        if let lastCostScanAt,
           now().timeIntervalSince(lastCostScanAt) < Constants.costScanInterval
        {
            return
        }
        lastCostScanAt = now()
        cancelCostScan()
        let scanGeneration = costScanGeneration
        // Captured before the detached task so the @MainActor store is not
        // referenced from the scan; resolves fresh, stale-on-failure, or no
        // catalog so the scan prices against live rates when available.
        let pricingLoader = pricingLoader
        let scanHomeDirectory = homeDirectory
        let trace = GitPerformanceTrace.begin("usage.cost.scan")

        let workerTask = Task.detached(priority: .utility) { () -> UsageQuotaCostEstimate in
            guard !Task.isCancelled else { return UsageQuotaCostEstimate(rows: []) }
            let pricing = await pricingLoader()
            guard !Task.isCancelled else { return UsageQuotaCostEstimate(rows: []) }
            return UsageQuotaCostScanner.estimate(
                homeDirectory: scanHomeDirectory,
                pricing: pricing
            )
        }
        costScanWorkerTask = workerTask

        let task = trackPendingTask { [weak self, workerTask] in
            defer { GitPerformanceTrace.end("usage.cost.scan", id: trace) }
            let estimates = await withTaskCancellationHandler {
                await workerTask.value
            } onCancel: {
                workerTask.cancel()
            }
            guard let self,
                  !Task.isCancelled,
                  scanGeneration == costScanGeneration,
                  showAIUsageQuotas
            else { return }
            costEstimates = estimates.rows.isEmpty ? nil : estimates
            if scanGeneration == costScanGeneration {
                costScanTask = nil
                costScanWorkerTask = nil
            }
        }
        costScanTask = task
    }

    private func finishRefresh(reason: RefreshReason, generation: Int) {
        guard generation == refreshGeneration else { return }
        isRefreshInFlight = false
        refreshTask = nil
        if reason == .windowPresented {
            lastPresentationRefreshAt = now()
        }
    }

    private func resolveSnapshot(_ fetched: UsageQuotaSnapshot) -> UsageQuotaSnapshot {
        if fetched.isAvailable {
            return fetched
        }

        if let cached = snapshotStore.load(providerID: fetched.providerID) {
            return cached.markingStale(note: fetched.statusNote ?? cached.statusNote)
        }

        return fetched
    }

    private static func fetchWithTimeout(
        provider: any UsageQuotaProviding,
        timeout: TimeInterval
    ) async -> UsageQuotaSnapshot {
        await withTaskGroup(of: UsageQuotaSnapshot?.self) { group in
            group.addTask { await provider.fetchSnapshot() }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            defer { group.cancelAll() }
            if let first = await group.next(), let snapshot = first {
                return snapshot
            }
            return .unavailable(providerID: provider.id, statusNote: "refresh timed out")
        }
    }
}
