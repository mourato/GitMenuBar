import Foundation

/// Runs the one-shot `agy -p /usage --output-format json` report used as the
/// Antigravity fallback when no language server or OAuth credentials exist.
enum AntigravityCLIUsageReport {
    static func resolveBinary(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let override = environment["ANTIGRAVITY_CLI_PATH"],
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override)
        {
            return override
        }

        var candidates: [String] = []
        if let path = environment["PATH"], !path.isEmpty {
            candidates += path.split(separator: ":").map { "\($0)/agy" }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates += [
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy"
        ]

        var seen = Set<String>()
        for candidate in candidates {
            guard seen.insert(candidate).inserted else { continue }
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func run(binary: String, timeout: TimeInterval) async -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "-p", "/usage",
            "--output-format", "json",
            "--print-timeout", "\(max(1, Int(timeout)))s"
        ]
        process.standardInput = FileHandle.nullDevice
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain stdout while the process runs so a full pipe buffer cannot stall it.
        let outputHandle = outputPipe.fileHandleForReading
        let output = Task.detached { outputHandle.readDataToEndOfFile() }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        let data = await output.value
        guard process.terminationStatus == 0 else { return nil }
        guard !data.isEmpty else { return nil }
        return Data(data.prefix(1_048_576))
    }
}
