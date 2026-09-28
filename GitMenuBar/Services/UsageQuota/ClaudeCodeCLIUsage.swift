import Foundation

enum ClaudeCodeCLIUsage {
    private static let timeout: TimeInterval = 8

    static func fetchSnapshot(
        homeDirectory: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) async -> UsageQuotaSnapshot? {
        guard let binary = await resolveBinary() else { return nil }
        guard let output = await capture(binary: binary, homeDirectory: homeDirectory) else { return nil }
        return snapshot(from: output, now: now())
    }

    static func snapshot(from output: String, now: Date = Date()) -> UsageQuotaSnapshot? {
        let clean = stripANSICodes(output).replacingOccurrences(of: "\r", with: "\n")
        let session = usageWindow(
            in: clean,
            labels: ["Current session"],
            label: "5h",
            durationSeconds: 5 * 3600
        )
        let weekly = usageWindow(
            in: clean,
            labels: ["Current week (all models)"],
            label: "7d",
            durationSeconds: 7 * 86400
        )
        let modelWindows = modelWindows(in: clean)
        guard session != nil || weekly != nil || !modelWindows.isEmpty else { return nil }

        return UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: UsageProviderID.claudeCode.displayName,
            sessionWindow: session,
            weeklyWindow: weekly,
            modelWindows: modelWindows,
            isAvailable: true,
            statusNote: "Claude Code CLI PTY /usage",
            fetchedAt: now
        )
    }

    private static func usageWindow(
        in text: String,
        labels: [String],
        label: String,
        durationSeconds: Int
    ) -> UsageWindow? {
        guard let usedPercent = percent(after: labels, in: text) else { return nil }
        return UsageWindow(
            remainingPercent: UsageQuotaFormatting.remainingPercent(fromUsed: Double(usedPercent)),
            resetAt: nil,
            label: label,
            durationSeconds: durationSeconds
        )
    }

    private static func modelWindows(in text: String) -> [UsageWindow] {
        let lines = text.components(separatedBy: .newlines)
        var windows: [UsageWindow] = []
        var seenModels = Set<String>()
        let pattern = #"Current week \(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex ..< line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges > 1,
                  let modelRange = Range(match.range(at: 1), in: line)
            else {
                continue
            }

            let modelName = String(line[modelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let modelKey = modelName.lowercased()
            guard !modelName.isEmpty, modelKey != "all models", seenModels.insert(modelKey).inserted else {
                continue
            }
            guard let usedPercent = percent(afterLine: index, in: lines) else { continue }
            let label = modelKey.contains("only") ? modelName : "\(modelName) only"
            windows.append(
                UsageWindow(
                    remainingPercent: UsageQuotaFormatting.remainingPercent(fromUsed: Double(usedPercent)),
                    resetAt: nil,
                    label: label,
                    durationSeconds: 7 * 86400
                )
            )
        }
        return windows
    }

    private static func percent(after labels: [String], in text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where labels.contains(where: { line.localizedStandardContains($0) }) {
            if let value = percent(afterLine: index, in: lines) {
                return value
            }
        }
        return nil
    }

    private static func percent(afterLine index: Int, in lines: [String]) -> Int? {
        let end = min(lines.count, index + 12)
        for (offset, candidate) in lines[index ..< end].enumerated() {
            if let value = percent(from: candidate) {
                return value
            }
            if offset > 0,
               candidate.localizedStandardContains("Current session") ||
               offset > 0 && candidate.localizedStandardContains("Current week")
            {
                break
            }
        }
        return nil
    }

    private static func percent(from line: String) -> Int? {
        let pattern = #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let valueRange = Range(match.range(at: 1), in: line),
              let rawValue = Double(line[valueRange])
        else {
            return nil
        }

        let clamped = max(0, min(100, rawValue))
        let lowercased = line.lowercased()
        if lowercased.contains("used") || lowercased.contains("spent") || lowercased.contains("consumed") {
            return Int(clamped.rounded())
        }
        if lowercased.contains("left") || lowercased.contains("remaining") || lowercased.contains("available") {
            return Int((100 - clamped).rounded())
        }
        return nil
    }

    private static func stripANSICodes(_ text: String) -> String {
        let pattern = String(UnicodeScalar(27)) + "\\[[0-?]*[ -/]*[@-~]"
        guard let csi = try? NSRegularExpression(pattern: pattern) else { return text }
        return csi.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }

    private static func resolveBinary() async -> URL? {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"],
           FileManager.default.isExecutableFile(atPath: override)
        {
            return URL(fileURLWithPath: override)
        }
        return await CodexExecutableLocator.locate("claude")
    }

    private static func capture(binary: URL, homeDirectory: URL) async -> String? {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let buffer = CaptureBuffer()
        let script = URL(fileURLWithPath: "/usr/bin/script")

        guard FileManager.default.isExecutableFile(atPath: script.path) else { return nil }
        process.executableURL = script
        process.arguments = ["-q", "/dev/null", binary.path]
        process.currentDirectoryURL = homeDirectory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "xterm-256color"
        ]) { _, new in new }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                buffer.append(data)
            }
        }
        process.terminationHandler = { _ in
            output.fileHandleForReading.readabilityHandler = nil
            buffer.finish(output.fileHandleForReading.readDataToEndOfFile())
        }

        do {
            try process.run()
            input.fileHandleForWriting.write(Data("/usage\r".utf8))
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let timeout = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.timeout, execute: timeout)
        let data = await buffer.wait()
        timeout.cancel()
        return String(data: data, encoding: .utf8)
    }
}

private final class CaptureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var result: Data?
    private var continuation: CheckedContinuation<Data, Never>?

    func append(_ chunk: Data) {
        lock.lock()
        defer { self.lock.unlock() }
        guard result == nil else { return }
        data.append(chunk)
    }

    func finish(_ trailingData: Data) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        data.append(trailingData)
        self.result = data
        let continuation = continuation
        self.continuation = nil
        let result = result ?? Data()
        lock.unlock()
        continuation?.resume(returning: result)
    }

    func wait() async -> Data {
        await withCheckedContinuation { continuation in
            self.lock.lock()
            if let result {
                self.lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                self.lock.unlock()
            }
        }
    }
}
