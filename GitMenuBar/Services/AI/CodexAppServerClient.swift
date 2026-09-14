import Foundation

enum CodexExecutableLocator {
    nonisolated static func locate(
        _ command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(command) }
        candidates += ["/opt/homebrew/bin", "/usr/local/bin"].map {
            URL(fileURLWithPath: $0).appendingPathComponent(command)
        }
        candidates += [".local/bin", ".npm-global/bin", ".volta/bin", ".bun/bin", ".cargo/bin"].map {
            home.appendingPathComponent($0).appendingPathComponent(command)
        }
        let nvmVersions = home.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvmVersions.path)) ?? []
        candidates += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map {
            nvmVersions.appendingPathComponent($0).appendingPathComponent("bin/\(command)")
        }

        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return candidate
        }

        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-ilc", "command -v \(command)"]
            process.currentDirectoryURL = home
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let output = Pipe()
            process.standardOutput = output
            do {
                try process.run()
            } catch {
                return nil
            }
            let watchdog = Task {
                try? await Task.sleep(for: .seconds(5))
                if process.isRunning {
                    process.terminate()
                }
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            guard process.terminationStatus == 0 else { return nil }
            let path = (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = URL(fileURLWithPath: path)
            return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }.value
    }
}

@MainActor
final class CodexAppServerClient {
    enum ClientError: LocalizedError {
        case executableMissing
        case launchFailed
        case processExited
        case requestFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .executableMissing:
                "Install the Codex CLI to use your ChatGPT account."
            case .launchFailed:
                "The Codex CLI could not start."
            case .processExited:
                "The Codex CLI stopped unexpectedly."
            case let .requestFailed(message):
                message
            case .timedOut:
                "The Codex CLI did not respond in time."
            }
        }
    }

    private struct PendingRequest {
        let continuation: CheckedContinuation<[String: CodexJSONValue], Error>
        let timeout: Task<Void, Never>
    }

    var onNotification: ((String, [String: CodexJSONValue]) -> Void)?
    var onExit: ((String) -> Void)?

    private let codexHome: URL?
    let workspace: URL
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var stderrBuffer = Data()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]

    init(codexHome: URL? = nil, workspace: URL) {
        self.codexHome = codexHome
        self.workspace = workspace
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start() async throws {
        if isRunning {
            return
        }
        guard let executable = await CodexExecutableLocator.locate("codex") else {
            throw ClientError.executableMissing
        }
        if isRunning {
            return
        }

        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspace.path)
            if let codexHome {
                try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexHome.path)
            }
        } catch {
            throw ClientError.launchFailed
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = [
            "-c", "check_for_update_on_startup=false",
            "-c", "features.apps=false",
            "-c", "features.plugins=false",
            "-c", "features.remote_plugin=false",
            "-c", "features.remote_plugins=false",
            "-c", "features.plugin_sharing=false",
            "-c", "features.shell_tool=false",
            "-c", "features.unified_exec=false",
            "-c", "features.browser_use=false",
            "-c", "features.in_app_browser=false",
            "-c", "features.computer_use=false",
            "-c", "features.image_generation=false",
            "-c", "features.multi_agent=false",
            "-c", "features.hooks=false",
            "-c", "features.workspace_dependencies=false",
            "-c", "memories.use_memories=false",
            "app-server"
        ]
        process.currentDirectoryURL = workspace
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        process.environment = ProcessInfo.processInfo.environment.merging([
            "NO_COLOR": "1",
            "PATH": [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", inheritedPath]
                .joined(separator: ":")
        ]) { _, new in new }
        if let codexHome {
            process.environment?["CODEX_HOME"] = codexHome.path
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeOutput(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeStderr(data) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.didExit(status: status) }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw ClientError.launchFailed
        }
        self.process = process
        input = stdin.fileHandleForWriting

        do {
            _ = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "gitmenubar",
                        "title": "GitMenuBar",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                    ],
                    "capabilities": ["experimentalApi": false]
                ]
            )
            try send(CodexAppServerProtocol.notification(method: "initialized"))
        } catch {
            stop()
            throw error
        }
    }

    func request(
        method: String,
        params: [String: Any] = [:],
        timeout: Duration = .seconds(30)
    ) async throws -> [String: CodexJSONValue] {
        guard isRunning else { throw ClientError.processExited }
        let id = nextID
        nextID += 1

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.timeoutRequest(id)
                }
                pending[id] = PendingRequest(continuation: continuation, timeout: timeoutTask)
                do {
                    try send(CodexAppServerProtocol.request(id: id, method: method, params: params))
                } catch {
                    finishRequest(id, with: .failure(error))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.finishRequest(id, with: .failure(CancellationError())) }
        }
    }

    func stop() {
        guard let process else { return }
        process.terminationHandler = nil
        cleanup(error: ClientError.processExited)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func send(_ data: Data) throws {
        guard let input else { throw ClientError.processExited }
        try input.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handle(CodexAppServerProtocol.parse(Data(line)))
        }
        guard outputBuffer.count <= 8 * 1_048_576 else {
            let message = "Codex sent an oversized response and was disconnected."
            onExit?(message)
            stop()
            return
        }
    }

    private func handle(_ message: CodexAppServerProtocol.Message) {
        switch message {
        case let .response(id, result):
            finishRequest(id, with: .success(result))
        case let .failure(id, message):
            finishRequest(id, with: .failure(ClientError.requestFailed(message)))
        case let .notification(method, params):
            onNotification?(method, params)
        case let .request(id, method, _):
            declineServerRequest(id: id, method: method)
        case .invalid:
            break
        }
    }

    private func declineServerRequest(id: CodexAppServerProtocol.RequestID, method: String) {
        let result: [String: Any]
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            result = ["decision": "cancel"]
        case "item/permissions/requestApproval":
            result = [
                "permissions": [
                    "fileSystem": ["entries": []],
                    "network": ["enabled": false]
                ]
            ]
        case "tool/requestUserInput":
            result = ["answers": [:]]
        default:
            try? send(CodexAppServerProtocol.errorResponse(id: id, message: "GitMenuBar does not expose Codex tools."))
            return
        }
        try? send(CodexAppServerProtocol.response(id: id, result: result))
    }

    private func consumeStderr(_ data: Data) {
        stderrBuffer.append(data)
        if stderrBuffer.count > 8192 {
            stderrBuffer.removeFirst(stderrBuffer.count - 8192)
        }
    }

    private func timeoutRequest(_ id: Int) {
        finishRequest(id, with: .failure(ClientError.timedOut))
    }

    private func finishRequest(_ id: Int, with result: Result<[String: CodexJSONValue], Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    private func didExit(status _: Int32) {
        onExit?(ClientError.processExited.localizedDescription)
        cleanup(error: ClientError.processExited)
    }

    private func cleanup(error: Error) {
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        process = nil
        input = nil
        outputBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
        let requests = pending
        pending.removeAll()
        for request in requests.values {
            request.timeout.cancel()
            request.continuation.resume(throwing: error)
        }
    }
}
