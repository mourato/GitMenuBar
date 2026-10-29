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
    enum CancellationMode: Sendable {
        case autoResume
        case holdUntilGate
    }

    let id: UsageProviderID
    private let lock = NSLock()
    private var storedSnapshot: UsageQuotaSnapshot
    private var storedFetchCount = 0
    private var storedOnFetch: (@Sendable () -> Void)?
    private var storedIsCancelled = false
    private var storedOnCancel: (@Sendable () -> Void)?
    private var pendingByFetch: [Int: CheckedContinuation<Void, Never>] = [:]
    private var defaultCancellationMode: CancellationMode = .autoResume
    private var cancellationModeByFetch: [Int: CancellationMode] = [:]
    private var activeFetches: Set<Int> = []
    private var completionContinuations: [CheckedContinuation<Void, Never>] = []

    init(id: UsageProviderID = .codex, snapshot: UsageQuotaSnapshot) {
        self.id = id
        storedSnapshot = snapshot
    }

    var snapshot: UsageQuotaSnapshot {
        get { lock.withLock { storedSnapshot } }
        set { lock.withLock { storedSnapshot = newValue } }
    }

    var fetchCount: Int {
        lock.withLock { storedFetchCount }
    }

    var isCancelled: Bool {
        lock.withLock { storedIsCancelled }
    }

    var onFetch: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnFetch } }
        set { lock.withLock { storedOnFetch = newValue } }
    }

    var onCancel: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnCancel } }
        set { lock.withLock { storedOnCancel = newValue } }
    }

    func setCancellationMode(_ mode: CancellationMode, forFetch fetchNumber: Int? = nil) {
        lock.withLock {
            if let fetchNumber {
                cancellationModeByFetch[fetchNumber] = mode
            } else {
                defaultCancellationMode = mode
            }
        }
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        let (fetchNumber, snapshotForRequest) = lock.withLock { () -> (Int, UsageQuotaSnapshot) in
            storedFetchCount += 1
            activeFetches.insert(storedFetchCount)
            return (storedFetchCount, storedSnapshot)
        }
        defer {
            lock.withLock {
                activeFetches.remove(fetchNumber)
                if activeFetches.isEmpty {
                    let continuations = completionContinuations
                    completionContinuations.removeAll()
                    for continuation in continuations {
                        continuation.resume()
                    }
                }
            }
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Register the continuation before notifying the test so opening
                // the gate cannot race with pending-state installation.
                let state = lock.withLock { () -> (
                    hook: (@Sendable () -> Void)?,
                    immediate: CheckedContinuation<Void, Never>?
                ) in
                    let hook = storedOnFetch
                    if Task.isCancelled {
                        return (hook: hook, immediate: continuation)
                    }
                    pendingByFetch[fetchNumber] = continuation
                    return (hook: hook, immediate: nil)
                }
                state.hook?()
                state.immediate?.resume()
            }
        } onCancel: {
            let (hook, continuation) = self.lock.withLock { () -> ((@Sendable () -> Void)?, CheckedContinuation<Void, Never>?) in
                self.storedIsCancelled = true
                let hook = self.storedOnCancel
                let mode = self.cancellationModeByFetch[fetchNumber] ?? self.defaultCancellationMode
                let continuation: CheckedContinuation<Void, Never>? = switch mode {
                case .autoResume:
                    self.pendingByFetch.removeValue(forKey: fetchNumber)
                case .holdUntilGate:
                    nil
                }
                return (hook, continuation)
            }
            hook?()
            continuation?.resume()
        }
        return snapshotForRequest
    }

    /// Releases a specific fetch's continuation.
    func openGate(forFetch fetchNumber: Int) {
        let continuation = lock.withLock {
            pendingByFetch.removeValue(forKey: fetchNumber)
        }
        continuation?.resume()
    }

    /// Releases all pending fetches; later cycles still block until opened.
    func openGate() {
        let continuations = lock.withLock {
            let all = Array(pendingByFetch.values)
            pendingByFetch.removeAll()
            return all
        }
        for continuation in continuations {
            continuation.resume()
        }
    }

    func awaitAllFetches() async {
        let shouldWait: Bool = lock.withLock { !activeFetches.isEmpty }
        guard shouldWait else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let immediateResume: Bool = lock.withLock {
                if activeFetches.isEmpty {
                    return true
                }
                completionContinuations.append(continuation)
                return false
            }
            if immediateResume {
                continuation.resume()
            }
        }
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
    private var storedIsCancelled = false
    private var storedOnCancel: (@Sendable () -> Void)?
    private var pending: CheckedContinuation<UsageQuotaModelsDevStore.PricingSource, Never>?
    private var activeLoads = 0
    private var completionContinuations: [CheckedContinuation<Void, Never>] = []

    var loadCount: Int {
        lock.withLock { storedLoadCount }
    }

    var isCancelled: Bool {
        lock.withLock { storedIsCancelled }
    }

    var onLoad: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnLoad } }
        set { lock.withLock { storedOnLoad = newValue } }
    }

    var onCancel: (@Sendable () -> Void)? {
        get { lock.withLock { storedOnCancel } }
        set { lock.withLock { storedOnCancel = newValue } }
    }

    func load() async -> UsageQuotaModelsDevStore.PricingSource {
        lock.withLock { activeLoads += 1 }
        defer {
            lock.withLock {
                activeLoads -= 1
                if activeLoads == 0 {
                    let continuations = completionContinuations
                    completionContinuations.removeAll()
                    for continuation in continuations {
                        continuation.resume()
                    }
                }
            }
        }

        return await withTaskCancellationHandler {
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
            let hook = self.lock.withLock {
                self.storedIsCancelled = true
                return self.storedOnCancel
            }
            hook?()
            self.resumePending()
        }
    }

    func openGate() {
        resumePending()
    }

    func awaitAllLoads() async {
        let shouldWait: Bool = lock.withLock { activeLoads > 0 }
        guard shouldWait else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let immediateResume: Bool = lock.withLock {
                if activeLoads == 0 {
                    return true
                }
                completionContinuations.append(continuation)
                return false
            }
            if immediateResume {
                continuation.resume()
            }
        }
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
