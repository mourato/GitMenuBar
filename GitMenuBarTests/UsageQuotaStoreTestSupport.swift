import Foundation
@testable import GitMenuBar

func writeCodexSessionFixture(to homeDirectory: URL, now: Date) throws {
    let monthStart = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: now)
    ) ?? now
    let timestamp = ISO8601DateFormatter().string(from: monthStart.addingTimeInterval(3600))
    let codexDirectory = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
    let lines = [
        #"{"timestamp":"\#(timestamp)","ordinal":1,"type":"turn_context","payload":{"turn_id":"t1","model":"gpt-6.1-sol"}}"#,
        #"{"timestamp":"\#(timestamp)","ordinal":2,"type":"token_usage_record","payload":{"turn_id":"t1","usage":{"input_tokens":1000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":100}}}"#
    ]
    try lines.joined(separator: "\n").write(
        to: codexDirectory.appendingPathComponent("rollout.jsonl"),
        atomically: true,
        encoding: .utf8
    )
}

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

/// Holds a cost scan at pricing resolution so tests can order it against a quota refresh.
final class GatedPricingLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLoadCount = 0
    private var storedOnLoad: (@Sendable () -> Void)?
    private var pending: CheckedContinuation<UsageQuotaModelsDevStore.PricingSource, Never>?

    var loadCount: Int {
        lock.withLock { storedLoadCount }
    }

    var onLoad: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnLoad } }
        set { lock.withLock { storedOnLoad = newValue } }
    }

    func load() async -> UsageQuotaModelsDevStore.PricingSource {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UsageQuotaModelsDevStore.PricingSource, Never>) in
                let state = lock.withLock { () -> (
                    hook: (@Sendable () -> Void)?,
                    immediate: CheckedContinuation<UsageQuotaModelsDevStore.PricingSource, Never>?
                ) in
                    storedLoadCount += 1
                    let hook = storedOnLoad
                    if Task.isCancelled {
                        return (hook: hook, immediate: continuation)
                    }
                    pending = continuation
                    return (hook: hook, immediate: nil)
                }
                state.hook?()
                state.immediate?.resume(returning: .bundled)
            }
        } onCancel: {
            resumePending()
        }
    }

    func openGate() {
        resumePending()
    }

    private func resumePending() {
        let continuation = lock.withLock {
            let continuation = pending
            pending = nil
            return continuation
        }
        continuation?.resume(returning: .bundled)
    }
}
