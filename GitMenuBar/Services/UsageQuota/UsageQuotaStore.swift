import Combine
import Foundation

@MainActor
final class UsageQuotaStore: ObservableObject {
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
    }

    @Published private(set) var snapshots: [UsageQuotaSnapshot] = []
    @Published var showAIUsageQuotas: Bool {
        didSet {
            guard showAIUsageQuotas != oldValue else { return }
            defaults.set(showAIUsageQuotas, forKey: AppPreferences.Keys.showAIUsageQuotas)
            handlePreferenceChange()
        }
    }

    @Published var showCodexUsageQuota: Bool {
        didSet {
            guard showCodexUsageQuota != oldValue else { return }
            defaults.set(showCodexUsageQuota, forKey: AppPreferences.Keys.showCodexUsageQuota)
            handlePreferenceChange()
        }
    }

    @Published var showCursorUsageQuota: Bool {
        didSet {
            guard showCursorUsageQuota != oldValue else { return }
            defaults.set(showCursorUsageQuota, forKey: AppPreferences.Keys.showCursorUsageQuota)
            handlePreferenceChange()
        }
    }

    @Published var showOpenRouterUsageQuota: Bool {
        didSet {
            guard showOpenRouterUsageQuota != oldValue else { return }
            defaults.set(showOpenRouterUsageQuota, forKey: AppPreferences.Keys.showOpenRouterUsageQuota)
            handlePreferenceChange()
        }
    }

    private let defaults: UserDefaults
    private let snapshotStore: UsageQuotaSnapshotStore
    private let providers: [any UsageQuotaProviding]
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        snapshotStore: UsageQuotaSnapshotStore = UsageQuotaSnapshotStore(),
        providers: [any UsageQuotaProviding] = [CodexUsageProvider(), CursorUsageProvider(), OpenRouterUsageProvider()]
    ) {
        self.defaults = defaults
        self.snapshotStore = snapshotStore
        self.providers = providers
        showAIUsageQuotas = defaults.object(forKey: AppPreferences.Keys.showAIUsageQuotas) as? Bool ?? false
        showCodexUsageQuota = defaults.object(forKey: AppPreferences.Keys.showCodexUsageQuota) as? Bool ?? true
        showCursorUsageQuota = defaults.object(forKey: AppPreferences.Keys.showCursorUsageQuota) as? Bool ?? true
        showOpenRouterUsageQuota = defaults.object(forKey: AppPreferences.Keys.showOpenRouterUsageQuota) as? Bool ?? true
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

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(reason: reason)
        }
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

    private func isProviderEnabled(_ providerID: UsageProviderID) -> Bool {
        switch providerID {
        case .codex:
            showCodexUsageQuota
        case .cursor:
            showCursorUsageQuota
        case .openrouter:
            showOpenRouterUsageQuota
        }
    }

    private func performRefresh(reason: RefreshReason) async {
        guard showAIUsageQuotas else { return }

        let activeProviders = enabledProviders()
        guard !activeProviders.isEmpty else {
            snapshots = []
            return
        }

        var merged: [UsageQuotaSnapshot] = []

        await withTaskGroup(of: UsageQuotaSnapshot.self) { group in
            for provider in activeProviders {
                group.addTask {
                    await Self.fetchWithTimeout(provider: provider, timeout: Constants.providerTimeout)
                }
            }

            for await snapshot in group {
                merged.append(self.mergeSnapshot(snapshot))
            }
        }

        merged.sort { $0.providerID.rawValue < $1.providerID.rawValue }
        snapshots = merged
        _ = reason
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
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
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
