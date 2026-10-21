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
    var showAIUsageQuotas: Bool {
        didSet {
            guard showAIUsageQuotas != oldValue else { return }
            defaults.set(showAIUsageQuotas, forKey: AppPreferences.Keys.showAIUsageQuotas)
            handlePreferenceChange()
        }
    }

    var showClaudeCodeUsageQuota: Bool {
        didSet {
            guard showClaudeCodeUsageQuota != oldValue else { return }
            defaults.set(showClaudeCodeUsageQuota, forKey: AppPreferences.Keys.showClaudeCodeUsageQuota)
            handlePreferenceChange()
        }
    }

    var showCodexUsageQuota: Bool {
        didSet {
            guard showCodexUsageQuota != oldValue else { return }
            defaults.set(showCodexUsageQuota, forKey: AppPreferences.Keys.showCodexUsageQuota)
            handlePreferenceChange()
        }
    }

    var showCursorUsageQuota: Bool {
        didSet {
            guard showCursorUsageQuota != oldValue else { return }
            defaults.set(showCursorUsageQuota, forKey: AppPreferences.Keys.showCursorUsageQuota)
            handlePreferenceChange()
        }
    }

    var showOpenRouterUsageQuota: Bool {
        didSet {
            guard showOpenRouterUsageQuota != oldValue else { return }
            defaults.set(showOpenRouterUsageQuota, forKey: AppPreferences.Keys.showOpenRouterUsageQuota)
            handlePreferenceChange()
        }
    }

    var showGeminiUsageQuota: Bool {
        didSet {
            guard showGeminiUsageQuota != oldValue else { return }
            defaults.set(showGeminiUsageQuota, forKey: AppPreferences.Keys.showGeminiUsageQuota)
            handlePreferenceChange()
        }
    }

    var showAntigravityUsageQuota: Bool {
        didSet {
            guard showAntigravityUsageQuota != oldValue else { return }
            defaults.set(showAntigravityUsageQuota, forKey: AppPreferences.Keys.showAntigravityUsageQuota)
            handlePreferenceChange()
        }
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
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var isRefreshInFlight = false
    @ObservationIgnored private var lastPresentationRefreshAt: Date?
    @ObservationIgnored private var lastCostScanAt: Date?

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
        pricingLoader: @escaping PricingLoader = { await UsageQuotaModelsDevStore.shared.loadOrFetch() }
    ) {
        self.defaults = defaults
        self.snapshotStore = snapshotStore
        self.providers = providers
        self.codexProvider = codexProvider
        self.now = now
        self.pricingLoader = pricingLoader
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

    func refresh(reason: RefreshReason = .manual) {
        guard showAIUsageQuotas else { return }
        switch reason {
        case .manual:
            // Manual stays a forced refresh: it may cancel and replace in-flight work.
            break
        case .windowPresented:
            guard !isRefreshInFlight else { return }
            if let lastPresentationRefreshAt,
               now().timeIntervalSince(lastPresentationRefreshAt) < Constants.refreshInterval
            {
                return
            }
        case .timer, .settingsEnabled, .contentAppeared:
            // Automatic requests coalesce with an in-flight cycle instead of
            // cancelling and restarting it; the cycle reconciles provider changes
            // before publishing its final snapshot.
            guard !isRefreshInFlight else { return }
        }

        // Only manual refreshes reach here with non-nil work in flight.
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshInFlight = true
        refreshTask = Task { [weak self] in
            await self?.performRefresh(reason: reason, generation: generation)
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
            snapshots = []
        }
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
        case .claudeCode:
            showClaudeCodeUsageQuota
        case .codex:
            showCodexUsageQuota
        case .cursor:
            showCursorUsageQuota
        case .openrouter:
            showOpenRouterUsageQuota
        case .gemini:
            showGeminiUsageQuota
        case .antigravity:
            showAntigravityUsageQuota
        }
    }

    func setProviderEnabled(_ isEnabled: Bool, for providerID: UsageProviderID) {
        switch providerID {
        case .claudeCode:
            showClaudeCodeUsageQuota = isEnabled
        case .codex:
            showCodexUsageQuota = isEnabled
        case .cursor:
            showCursorUsageQuota = isEnabled
        case .openrouter:
            showOpenRouterUsageQuota = isEnabled
        case .gemini:
            showGeminiUsageQuota = isEnabled
        case .antigravity:
            showAntigravityUsageQuota = isEnabled
        }
    }

    private func performRefresh(reason: RefreshReason, generation: Int) async {
        guard showAIUsageQuotas else {
            finishRefresh(reason: reason, generation: generation)
            return
        }
        let trace = GitPerformanceTrace.begin("usage.quota.refresh")
        defer { GitPerformanceTrace.end("usage.quota.refresh", id: trace) }

        let activeProviders = enabledProviders()
        guard !activeProviders.isEmpty else {
            snapshots = []
            finishRefresh(reason: reason, generation: generation)
            return
        }

        var merged = await fetchSnapshots(for: activeProviders)
        var fetchedProviderIDs = Set(activeProviders.map(\.id))
        var currentProviderIDs = fetchedProviderIDs

        // A settings change can arrive while a provider fetch is suspended.
        // Reconcile until no provider was added during the previous fetch.
        while true {
            let currentProviders = enabledProviders()
            currentProviderIDs = Set(currentProviders.map(\.id))
            let newlyEnabledProviders = currentProviders.filter { !fetchedProviderIDs.contains($0.id) }
            guard !newlyEnabledProviders.isEmpty else { break }

            fetchedProviderIDs.formUnion(newlyEnabledProviders.map(\.id))
            let newlyEnabledSnapshots = await fetchSnapshots(for: newlyEnabledProviders)
            merged.append(contentsOf: newlyEnabledSnapshots)
        }
        merged.removeAll { !currentProviderIDs.contains($0.providerID) }

        merged.sort { $0.providerID.rawValue < $1.providerID.rawValue }
        guard generation == refreshGeneration else { return }
        snapshots = merged
        finishRefresh(reason: reason, generation: generation)
        refreshCostEstimates(generation: generation)
    }

    private func fetchSnapshots(for providers: [any UsageQuotaProviding]) async -> [UsageQuotaSnapshot] {
        await withTaskGroup(of: UsageQuotaSnapshot.self, returning: [UsageQuotaSnapshot].self) { group in
            for provider in providers {
                group.addTask {
                    await Self.fetchWithTimeout(provider: provider, timeout: Constants.providerTimeout)
                }
            }

            var merged: [UsageQuotaSnapshot] = []
            for await snapshot in group {
                merged.append(mergeSnapshot(snapshot))
            }
            return merged
        }
    }

    /// Monthly spend estimate rides along without holding provider-refresh timing hostage.
    /// The scan gate is time-based for every reason: while the last scan is still
    /// fresh, a manual quota refresh only re-queries providers instead of also
    /// enumerating the JSONL sessions again.
    private func refreshCostEstimates(generation: Int) {
        if let lastCostScanAt,
           now().timeIntervalSince(lastCostScanAt) < Constants.costScanInterval
        {
            return
        }
        lastCostScanAt = now()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        // Captured before the detached task so the @MainActor store is not
        // referenced from the scan; resolves fresh, stale-on-failure, or no
        // catalog so the scan prices against live rates when available.
        let pricingLoader = pricingLoader
        let trace = GitPerformanceTrace.begin("usage.cost.scan")
        Task { [weak self] in
            defer { GitPerformanceTrace.end("usage.cost.scan", id: trace) }
            let estimates = await Task.detached(priority: .utility) {
                let pricing = await pricingLoader()
                return UsageQuotaCostScanner.estimate(
                    homeDirectory: homeDirectory,
                    pricing: pricing
                )
            }.value
            guard let self, generation == refreshGeneration else { return }
            costEstimates = estimates.rows.isEmpty ? nil : estimates
        }
    }

    private func finishRefresh(reason: RefreshReason, generation: Int) {
        guard generation == refreshGeneration else { return }
        isRefreshInFlight = false
        refreshTask = nil
        if reason == .windowPresented {
            lastPresentationRefreshAt = now()
        }
    }

    private func mergeSnapshot(_ fetched: UsageQuotaSnapshot) -> UsageQuotaSnapshot {
        if fetched.isAvailable {
            snapshotStore.save(fetched)
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
            group.addTask {
                await provider.fetchSnapshot()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }

            defer { group.cancelAll() }

            // First completed child wins: a non-nil snapshot from the provider, or
            // nil from the timeout task. Skipping nil used to ignore timeouts entirely.
            if let first = await group.next() {
                if let snapshot = first {
                    return snapshot
                }
                return .unavailable(providerID: provider.id, statusNote: "refresh timed out")
            }

            return .unavailable(providerID: provider.id, statusNote: "refresh timed out")
        }
    }
}
