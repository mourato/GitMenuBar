import CoreServices
import Foundation
import Synchronization

enum MonitoredProjectFileRouter {
    static func affectedProjects(
        for changedPaths: [String],
        projects: [ProjectReference]
    ) -> [ProjectReference] {
        let normalizedPaths = changedPaths.map(RecentProjectsStore.normalize)
        return projects.filter { project in
            normalizedPaths.contains { path in
                path == project.path
                    || (project.path == "/" ? path.hasPrefix("/") : path.hasPrefix(project.path + "/"))
            }
        }
    }
}

private final class MonitoredProjectFileWatcherContext: Sendable {
    let handler: @Sendable ([String], Bool) -> Void

    init(handler: @escaping @Sendable ([String], Bool) -> Void) {
        self.handler = handler
    }
}

final class MonitoredProjectFileEventRelay: Sendable {
    typealias Handler = @MainActor @Sendable ([String], Bool) -> Void

    private struct PendingDelivery: Sendable {
        var paths = Set<String>()
        var requiresFullRefresh = false
        var deliveryScheduled = false
    }

    private let handler: Handler
    private let pending = Mutex<PendingDelivery>(PendingDelivery())

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func enqueue(paths: [String], requiresFullRefresh: Bool) {
        let shouldScheduleDelivery = pending.withLock { state -> Bool in
            state.paths.formUnion(paths)
            state.requiresFullRefresh = state.requiresFullRefresh || requiresFullRefresh
            guard !state.deliveryScheduled else { return false }
            state.deliveryScheduled = true
            return true
        }

        guard shouldScheduleDelivery else { return }
        Task { @MainActor [weak self] in
            self?.deliver()
        }
    }

    @MainActor
    private func deliver() {
        let (paths, requiresFullRefresh) = pending.withLock { state -> ([String], Bool) in
            let paths = Array(state.paths)
            let requiresFullRefresh = state.requiresFullRefresh
            state.paths.removeAll()
            state.requiresFullRefresh = false
            state.deliveryScheduled = false
            return (paths, requiresFullRefresh)
        }

        handler(paths, requiresFullRefresh)
    }
}

// FSEventStream's C callback has six parameters by API contract.
// swiftlint:disable function_parameter_count
private func monitoredProjectFileWatcherCallback(
    _: FSEventStreamRef,
    contextInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>
) {
    guard let contextInfo else { return }
    let context = Unmanaged<MonitoredProjectFileWatcherContext>
        .fromOpaque(contextInfo)
        .takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
    let changedPaths = (0 ..< min(numEvents, paths.count)).compactMap { paths[$0] as? String }
    let recoveryFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped
            | kFSEventStreamEventFlagRootChanged
    )
    let requiresFullRefresh = (0 ..< numEvents).contains { index in
        eventFlags[index] & recoveryFlags != 0
    }
    context.handler(changedPaths, requiresFullRefresh)
}

// swiftlint:enable function_parameter_count

/// Lifecycle methods are called by the Main Actor-owned monitor store.
/// The FSEvents callback only reads the immutable context retained by the stream.
final class MonitoredProjectFileWatcher {
    typealias EventHandler = @Sendable ([String], Bool) -> Void

    private let eventHandler: EventHandler
    private let eventQueue = DispatchQueue(
        label: "com.mourato.GitMenuBar.monitored-project-file-watcher",
        qos: .utility
    )
    private var stream: FSEventStreamRef?
    private var context: MonitoredProjectFileWatcherContext?

    init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
    }

    func reconfigure(projects: [ProjectReference]) {
        stop()
        guard !projects.isEmpty else { return }

        let context = MonitoredProjectFileWatcherContext(handler: eventHandler)
        var streamContext = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(context).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                return UnsafeRawPointer(
                    Unmanaged<MonitoredProjectFileWatcherContext>
                        .fromOpaque(UnsafeMutableRawPointer(mutating: info))
                        .retain()
                        .toOpaque()
                )
            },
            release: { info in
                guard let info else { return }
                Unmanaged<MonitoredProjectFileWatcherContext>
                    .fromOpaque(UnsafeMutableRawPointer(mutating: info))
                    .release()
            },
            copyDescription: nil
        )
        let paths = projects.map(\.path) as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            nil,
            monitoredProjectFileWatcherCallback,
            &streamContext,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0,
            flags
        ) else {
            eventHandler([], true)
            return
        }

        self.context = context
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        guard FSEventStreamStart(stream) else {
            stop()
            eventHandler([], true)
            return
        }
    }

    func stop() {
        guard let stream else {
            context = nil
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        context = nil
    }

    deinit {
        stop()
    }
}
