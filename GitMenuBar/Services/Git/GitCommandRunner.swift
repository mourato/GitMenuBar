import Foundation
import os.log
import Synchronization

private final class GitPathCommandLockRegistry: Sendable {
    private let locks = Mutex<[String: DispatchSemaphore]>([:])

    func lock(for directory: String) -> DispatchSemaphore {
        let path = directory.isEmpty ? "" : URL(fileURLWithPath: directory).standardizedFileURL.path
        return locks.withLock { registry in
            if let existing = registry[path] {
                return existing
            }
            let created = DispatchSemaphore(value: 1)
            registry[path] = created
            return created
        }
    }
}

enum GitPerformanceTrace {
    private static let log = OSLog(subsystem: "com.gitmenubar.app", category: "Performance")

    static func begin(_ name: StaticString) -> OSSignpostID? {
        guard log.signpostsEnabled else { return nil }
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID?) {
        guard let id else { return }
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    static func event(_ name: StaticString, id: OSSignpostID?) {
        guard let id else { return }
        os_signpost(.event, log: log, name: name, signpostID: id)
    }

    static func commandResult(id: OSSignpostID?, family: String, succeeded: Bool) {
        guard let id else { return }
        os_signpost(
            .event,
            log: log,
            name: "git.command.result",
            signpostID: id,
            "%{public}s %{public}d",
            family,
            succeeded ? 1 : 0
        )
    }

    static func commandFamily(for args: [String]) -> String {
        switch args.first {
        case "add", "branch", "cat-file", "checkout", "clone", "commit", "config", "diff",
             "fetch", "init", "log", "ls-files", "merge", "pull", "push", "reflog", "remote",
             "reset", "rev-parse", "show", "stash", "status", "switch":
            args[0]
        default:
            "other"
        }
    }
}

final class GitCommandRunner: Sendable {
    // ponytail: one semaphore per touched path; replace with a weak registry only if path churn is measurable.
    private static let pathLockRegistry = GitPathCommandLockRegistry()

    func runGitCommand(
        in directory: String,
        args: [String],
        additionalEnvironment: [String: String] = [:]
    ) -> (output: String, failure: Bool) {
        let pathLock = Self.pathLockRegistry.lock(for: directory)
        pathLock.wait()
        defer { pathLock.signal() }

        return runCommand(
            in: directory,
            executable: "/usr/bin/git",
            args: args,
            additionalEnvironment: additionalEnvironment
        )
    }

    func runCommand(
        in directory: String,
        executable: String,
        args: [String],
        additionalEnvironment: [String: String] = [:]
    ) -> (output: String, failure: Bool) {
        let task = Process()
        task.launchPath = executable
        task.arguments = args
        task.currentDirectoryPath = directory
        var environment = ProcessInfo.processInfo.environment

        for (key, value) in additionalEnvironment {
            environment[key] = value
        }

        if !environment.isEmpty {
            task.environment = environment
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        let commandTrace = GitPerformanceTrace.begin("git.command")
        let commandFamily = GitPerformanceTrace.commandFamily(for: args)

        do {
            try task.run()
        } catch {
            GitPerformanceTrace.commandResult(id: commandTrace, family: commandFamily, succeeded: false)
            GitPerformanceTrace.end("git.command", id: commandTrace)
            return ("Failed to execute git command: \(error.localizedDescription)", true)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        task.waitUntilExit()
        let status = task.terminationStatus

        GitPerformanceTrace.commandResult(id: commandTrace, family: commandFamily, succeeded: status == 0)
        GitPerformanceTrace.end("git.command", id: commandTrace)

        return (output, status != 0)
    }
}
