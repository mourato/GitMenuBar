import Darwin
import Foundation

// MARK: - Process Querying Protocol & Models

struct RunningAgentProcess: Sendable, Equatable {
    let pid: pid_t
    let name: String
    let binaryPath: String
    let cwd: String
    let arguments: [String]

    init(pid: pid_t, name: String, binaryPath: String, cwd: String, arguments: [String] = []) {
        self.pid = pid
        self.name = name
        self.binaryPath = binaryPath
        self.cwd = cwd
        self.arguments = arguments
    }
}

protocol AgentProcessQuerying: Sendable {
    func runningProcesses() async -> [RunningAgentProcess]
}

// MARK: - Darwin Process Scanner

struct DarwinAgentProcessScanner: AgentProcessQuerying {
    func runningProcesses() async -> [RunningAgentProcess] {
        let task = Task.detached(priority: .utility) { Self.scanProcesses() }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func processArguments(pid: pid_t) -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else { return [] }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &bytes, &size, nil, 0) == 0 else { return [] }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return [] }
        var offset = MemoryLayout<Int32>.size
        // KERN_PROCARGS2 stores executable path, padding, then argc NUL-terminated arguments.
        while offset < size, bytes[offset] != 0 {
            offset += 1
        }
        while offset < size, bytes[offset] == 0 {
            offset += 1
        }
        var arguments: [String] = []
        for _ in 0 ..< argc {
            let start = offset
            while offset < size, bytes[offset] != 0 {
                offset += 1
            }
            guard offset < size, let argument = String(bytes: bytes[start ..< offset], encoding: .utf8) else { return [] }
            arguments.append(argument)
            offset += 1
        }
        return arguments
    }

    private static func scanProcesses() -> [RunningAgentProcess] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }

        let capacity = max(Int(count) / MemoryLayout<pid_t>.size + 64, 256)
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesWritten = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard bytesWritten > 0 else { return [] }
        let totalPids = min(capacity, Int(bytesWritten) / MemoryLayout<pid_t>.size)

        var results: [RunningAgentProcess] = []
        var nameBuffer = [CChar](repeating: 0, count: 1024)
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        for index in 0 ..< totalPids {
            guard !Task.isCancelled else { return [] }
            let pid = pids[index]
            guard pid > 0 else { continue }

            let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = nameLen > 0 ? String(cString: nameBuffer) : ""
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let binaryPath = pathLen > 0 ? String(cString: pathBuffer) : ""

            guard AgentActivityDetector.isCandidateAgentProcess(name: name, binaryPath: binaryPath)
                || URL(fileURLWithPath: binaryPath).lastPathComponent == "node" else { continue }
            let arguments = processArguments(pid: pid)
            guard AgentActivityDetector.harness(forProcessName: name, binaryPath: binaryPath, arguments: arguments) != nil else {
                continue
            }

            var vpi = proc_vnodepathinfo()
            let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            var cwd = ""
            if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, size) == size {
                withUnsafePointer(to: &vpi.pvi_cdir.vip_path) { ptr in
                    cwd = ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                }
            }
            results.append(RunningAgentProcess(pid: pid, name: name, binaryPath: binaryPath, cwd: cwd, arguments: arguments))
        }
        return results
    }
}

// MARK: - Agent Activity Detector Service

actor AgentActivityDetector {
    static let recentWindowSeconds: TimeInterval = 2 * 3600

    private let processQuerier: any AgentProcessQuerying
    private let sessionQuerier: any AgentSessionQuerying
    private let nowProvider: @Sendable () -> Date

    init(
        processQuerier: any AgentProcessQuerying = DarwinAgentProcessScanner(),
        sessionQuerier: any AgentSessionQuerying = SystemAgentSessionQuerier(),
        nowProvider: @Sendable @escaping () -> Date = Date.init
    ) {
        self.processQuerier = processQuerier
        self.sessionQuerier = sessionQuerier
        self.nowProvider = nowProvider
    }

    func detectAgents(for projectPaths: [String]) async -> [String: [AgentProjectActivity]] {
        guard !Task.isCancelled, !projectPaths.isEmpty else { return [:] }
        let now = nowProvider()

        async let runningProcessesAsync = processQuerier.runningProcesses()
        async let recentSessionsAsync = sessionQuerier.recentActivities(for: projectPaths, now: now)

        let runningProcesses = await runningProcessesAsync
        let recentSessions = await recentSessionsAsync
        var finalResults: [String: [AgentProjectActivity]] = [:]

        for path in projectPaths {
            let runningForProject = findRunningActivities(in: runningProcesses, for: path)
            let recentForProject = recentSessions[path] ?? []
            let merged = mergeActivities(running: runningForProject, recent: recentForProject)

            finalResults[path] = merged
        }

        return finalResults
    }

    private func findRunningActivities(
        in processes: [RunningAgentProcess],
        for projectPath: String
    ) -> [AgentProjectActivity] {
        var runningByHarness: [AgentHarnessID: AgentProjectActivity] = [:]

        for process in processes {
            // Multi-project servers' launch cwd does not identify their active projects.
            guard process.name != "codex-app-server",
                  URL(fileURLWithPath: process.binaryPath).lastPathComponent != "codex-app-server",
                  Self.isMatchingPath(processCwd: process.cwd, projectPath: projectPath),
                  let harness = Self.harness(forProcessName: process.name, binaryPath: process.binaryPath, arguments: process.arguments),
                  harness != .codex || !process.arguments.dropFirst().contains("app-server") else { continue }
            if runningByHarness[harness] == nil {
                runningByHarness[harness] = AgentProjectActivity(harness: harness, status: .running)
            }
        }
        return Array(runningByHarness.values)
    }

    private func mergeActivities(
        running: [AgentProjectActivity],
        recent: [AgentProjectActivity]
    ) -> [AgentProjectActivity] {
        var mergedByHarness: [AgentHarnessID: AgentProjectActivity] = [:]

        for activity in running {
            mergedByHarness[activity.harness] = activity
        }

        for activity in recent {
            if let existing = mergedByHarness[activity.harness] {
                if !existing.status.isRunning,
                   let existingDate = existing.status.lastActivityDate,
                   let newDate = activity.status.lastActivityDate,
                   newDate > existingDate
                {
                    mergedByHarness[activity.harness] = activity
                }
            } else {
                mergedByHarness[activity.harness] = activity
            }
        }

        return mergedByHarness.values.sorted { first, second in
            if first.status.isRunning != second.status.isRunning {
                return first.status.isRunning && !second.status.isRunning
            }
            let firstDate = first.status.lastActivityDate ?? .distantPast
            let secondDate = second.status.lastActivityDate ?? .distantPast
            if firstDate != secondDate {
                return firstDate > secondDate
            }
            return first.harness.rawValue < second.harness.rawValue
        }
    }

    // MARK: - Static Helpers & Classifiers

    static func harness(forProcessName processName: String, binaryPath: String, arguments: [String] = []) -> AgentHarnessID? {
        let name = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerName = name.lowercased()
        let binaryName = URL(fileURLWithPath: binaryPath).lastPathComponent.lowercased()

        if lowerName.contains("agy_acp_server") || binaryName.contains("agy_acp_server") ||
            lowerName.contains("localharness_external") || binaryName.contains("localharness_external")
        {
            return .antigravity
        }

        let nativeClaude = binaryPath.contains("/.local/share/claude/versions/")
            && URL(fileURLWithPath: binaryPath).deletingLastPathComponent().lastPathComponent == "versions"
        let npmClaude = binaryName == "node" && arguments.dropFirst().contains {
            $0.hasSuffix("/@anthropic-ai/claude-code/cli.js")
        }
        if lowerName == "claude" || binaryName == "claude" ||
            lowerName == "claude-code" || binaryName == "claude-code" || nativeClaude || npmClaude
        {
            return .claudeCode
        }

        if lowerName == "codex" || binaryName == "codex" ||
            lowerName == "codex-app-server" || binaryName == "codex-app-server"
        {
            return .codex
        }

        if lowerName == "opencode" || binaryName == "opencode" {
            return .opencode
        }

        if lowerName == "cursor-agent" || binaryName == "cursor-agent" {
            return .cursor
        }

        return nil
    }

    static func isCandidateAgentProcess(name: String, binaryPath: String) -> Bool {
        harness(forProcessName: name, binaryPath: binaryPath) != nil
    }

    static func parseEpochTimestamp(rawTime: Int64) -> Date {
        if rawTime > 10_000_000_000 {
            Date(timeIntervalSince1970: Double(rawTime) / 1000.0)
        } else {
            Date(timeIntervalSince1970: Double(rawTime))
        }
    }

    static func normalizePath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized
        let resolved = url.path
        if resolved.count > 1, resolved.hasSuffix("/") {
            return String(resolved.dropLast())
        }
        return resolved
    }

    static func isMatchingPath(processCwd: String, projectPath: String) -> Bool {
        guard !processCwd.isEmpty, !projectPath.isEmpty else { return false }
        let normCwd = normalizePath(processCwd)
        let normProj = normalizePath(projectPath)
        guard !normCwd.isEmpty, !normProj.isEmpty else { return false }

        if normProj == "/" {
            return normCwd == "/"
        }
        return normCwd == normProj || normCwd.hasPrefix(normProj + "/")
    }

    static func isWithinRecentThreshold(date: Date, relativeTo now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(date)
        return elapsed >= -60 && elapsed <= recentWindowSeconds
    }

    static func candidateSlugs(for projectPath: String) -> [String] {
        let norm = normalizePath(projectPath)
        var slugs = Set<String>()

        let slashReplaced = norm.replacingOccurrences(of: "/", with: "-")
        slugs.insert(slashReplaced)

        let trimmedLeadingDash = slashReplaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if !trimmedLeadingDash.isEmpty {
            slugs.insert(trimmedLeadingDash)
        }

        let nonAlphanumericReplaced = String(norm.map { ($0.isLetter || $0.isNumber) ? $0 : "-" })
        slugs.insert(nonAlphanumericReplaced)
        let trimmedNonAlpha = nonAlphanumericReplaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if !trimmedNonAlpha.isEmpty {
            slugs.insert(trimmedNonAlpha)
        }

        if projectPath != norm {
            let rawSlash = projectPath.replacingOccurrences(of: "/", with: "-")
            slugs.insert(rawSlash)
            let trimmedRaw = rawSlash.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if !trimmedRaw.isEmpty {
                slugs.insert(trimmedRaw)
            }
        }

        return Array(slugs)
    }
}
