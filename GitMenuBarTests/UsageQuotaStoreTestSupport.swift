import Foundation
@testable import GitMenuBar

/// Fetch-counting provider whose fetch blocks until `openGate` is called, so
/// tests can hold a refresh cycle in flight deterministically. All mutable
/// state is guarded by one lock; `@unchecked` covers the lock-protected
/// cross-task state of this test-only fake.
final class GatedUsageQuotaProvider: UsageQuotaProviding, @unchecked Sendable {
    let id: UsageProviderID
    private let lock = NSLock()
    private let storedSnapshot: UsageQuotaSnapshot
    private var storedFetchCount = 0
    private var storedOnFetch: (@Sendable () -> Void)?
    private var pending: CheckedContinuation<Void, Never>?

    init(id: UsageProviderID = .codex, snapshot: UsageQuotaSnapshot) {
        self.id = id
        storedSnapshot = snapshot
    }

    var fetchCount: Int {
        lock.withLock { storedFetchCount }
    }

    var onFetch: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnFetch } }
        set { lock.withLock { storedOnFetch = newValue } }
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Register the continuation before notifying the test so opening
                // the gate cannot race with pending-state installation.
                let state = lock.withLock { () -> (
                    hook: (@Sendable () -> Void)?,
                    immediate: CheckedContinuation<Void, Never>?
                ) in
                    storedFetchCount += 1
                    let hook = storedOnFetch
                    if Task.isCancelled {
                        return (hook: hook, immediate: continuation)
                    }
                    pending = continuation
                    return (hook: hook, immediate: nil)
                }
                state.hook?()
                state.immediate?.resume()
            }
        } onCancel: {
            // Cancelled fetches wake without the gate, so later cycles still block.
            self.resumePending()
        }
        return lock.withLock { storedSnapshot }
    }

    /// Releases the pending fetch; a later fetch re-checks cancellation itself.
    func openGate() {
        resumePending()
    }

    private func resumePending() {
        let woke = lock.withLock {
            let woke = pending
            pending = nil
            return woke
        }
        woke?.resume()
    }
}

/// Counts pricing loads so tests can observe whether the cost scan ran.
/// `@unchecked` covers the lock-protected counters of this test-only fake.
final class CountingPricingLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLoadCount = 0
    private var storedOnLoad: (@Sendable () -> Void)?

    var loadCount: Int {
        lock.withLock { storedLoadCount }
    }

    var onLoad: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnLoad } }
        set { lock.withLock { storedOnLoad = newValue } }
    }

    func load() -> UsageQuotaModelsDevStore.PricingSource {
        let hook = lock.withLock {
            storedLoadCount += 1
            return storedOnLoad
        }
        hook?()
        return .bundled
    }
}
