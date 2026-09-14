import Combine
import Foundation

@MainActor
protocol ChatGPTCommitGenerating: AnyObject {
    func generateCommitResponse(prompt: String, model: String, reasoningEffort: String?) async throws -> String
}

@MainActor
final class ChatGPTSubscriptionManager: ObservableObject, ChatGPTCommitGenerating {
    private static let idleShutdown: Duration = .seconds(600)

    private let client: CodexAppServerClient
    private let turns: CodexTurnRunner
    private var refreshTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    @Published private(set) var phase: ChatGPTSubscription.Phase = .idle
    @Published private(set) var account: ChatGPTSubscription.Account?
    @Published private(set) var models: [ChatGPTSubscription.Model] = []

    init(supportDirectory: URL? = nil) {
        let supportDirectory = supportDirectory ?? Self.defaultSupportDirectory()
        let root = supportDirectory.appendingPathComponent("InstalledAI/Codex", isDirectory: true)
        let workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        client = CodexAppServerClient(workspace: workspace)
        turns = CodexTurnRunner(client: client)

        turns.connect = { [weak self] in
            guard let self else { throw CancellationError() }
            try await ensureConnected()
            return models
        }
        turns.onTurnEnded = { [weak self] in
            self?.scheduleIdleShutdown()
        }
        client.onNotification = { [weak self] method, params in
            self?.handleNotification(method: method, params: params)
        }
        client.onExit = { [weak self] message in
            self?.turns.reset()
            self?.account = nil
            self?.models = []
            self?.phase = .failed(message)
        }
    }

    var isConnected: Bool {
        phase == .connected && account != nil
    }

    @discardableResult
    func refresh() -> Task<Void, Never> {
        refreshTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await refreshNow()
        }
        refreshTask = task
        return task
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        idleTask?.cancel()
        idleTask = nil
        turns.reset()
        client.stop()
        account = nil
        models = []
        phase = .idle
    }

    func generateCommitResponse(
        prompt: String,
        model: String,
        reasoningEffort: String?
    ) async throws -> String {
        idleTask?.cancel()
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else { throw AIError.modelNotConfigured }
        try await ensureConnected()

        guard let availableModel = models.first(where: { $0.id == normalizedModel }) else {
            throw AIError.requestFailed("\(normalizedModel) is no longer available in your ChatGPT subscription.")
        }
        return try await turns.generate(
            prompt: prompt,
            model: normalizedModel,
            reasoningEffort: availableModel.resolvedEffort(reasoningEffort)
        )
    }

    static func models(from response: [String: CodexJSONValue]) -> [ChatGPTSubscription.Model] {
        (response["data"]?.arrayValue ?? []).compactMap { value in
            guard let raw = value.objectValue,
                  let id = raw["model"]?.stringValue,
                  !id.isEmpty else { return nil }

            let efforts = (raw["supportedReasoningEfforts"]?.arrayValue ?? []).compactMap { value -> ChatGPTSubscription.Effort? in
                guard let raw = value.objectValue,
                      let id = raw["reasoningEffort"]?.stringValue,
                      !id.isEmpty else { return nil }
                return ChatGPTSubscription.Effort(
                    id: id,
                    detail: raw["description"]?.stringValue
                )
            }
            return ChatGPTSubscription.Model(
                id: id,
                name: raw["displayName"]?.stringValue ?? id,
                efforts: efforts,
                defaultEffort: raw["defaultReasoningEffort"]?.stringValue,
                isDefault: raw["isDefault"]?.boolValue ?? false
            )
        }
    }

    private static func defaultSupportDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GitMenuBar", isDirectory: true)
    }

    private func ensureConnected() async throws {
        idleTask?.cancel()
        try await client.start()
        if account == nil {
            let response = try await client.request(method: "account/read", params: ["refreshToken": false])
            guard let rawAccount = response["account"]?.objectValue else {
                phase = .signedOut
                throw AIError.chatGPTUnavailable
            }
            account = ChatGPTSubscription.Account(
                email: rawAccount["email"]?.stringValue,
                plan: rawAccount["planType"]?.stringValue ?? rawAccount["type"]?.stringValue ?? ""
            )
            phase = .connected
            await loadModels()
        }
        guard account != nil else { throw AIError.chatGPTUnavailable }
    }

    private func refreshNow() async {
        phase = .starting
        do {
            try await client.start()
            let response = try await client.request(method: "account/read", params: ["refreshToken": false])
            guard let rawAccount = response["account"]?.objectValue else {
                account = nil
                models = []
                phase = .signedOut
                client.stop()
                return
            }
            account = ChatGPTSubscription.Account(
                email: rawAccount["email"]?.stringValue,
                plan: rawAccount["planType"]?.stringValue ?? rawAccount["type"]?.stringValue ?? ""
            )
            phase = .connected
            await loadModels()
            scheduleIdleShutdown()
        } catch is CancellationError {
            // Cancellation has no verdict; the caller owns the replacement state.
        } catch let error as AIError {
            account = nil
            models = []
            phase = error == .chatGPTUnavailable ? .signedOut : .failed(error.localizedDescription)
        } catch {
            account = nil
            models = []
            phase = .failed(Self.userFacing(error))
        }
    }

    private func loadModels() async {
        do {
            let response = try await client.request(
                method: "model/list",
                params: ["includeHidden": false, "limit": 100]
            )
            models = Self.models(from: response)
        } catch is CancellationError {
            return
        } catch {
            models = []
        }
    }

    private func handleNotification(method: String, params: [String: CodexJSONValue]) {
        if method == "account/updated" {
            refresh()
        } else {
            turns.handle(method: method, params: params)
        }
    }

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleShutdown)
            guard !Task.isCancelled, let self, !self.turns.isActive else { return }
            turns.reset()
            client.stop()
        }
    }

    private static func userFacing(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "The ChatGPT account connection failed."
    }
}

@MainActor
final class CodexTurnRunner {
    private final class TurnToken: Sendable {}

    var connect: (@MainActor () async throws -> [ChatGPTSubscription.Model])?
    var onTurnEnded: (@MainActor () -> Void)?

    private let client: CodexAppServerClient
    private var activeContinuation: CheckedContinuation<String, Error>?
    private var activeToken: TurnToken?
    private var activeThreadID: String?
    private var activeTurnID: String?
    private var pendingInterruptThreadID: String?
    private var turnStartTask: Task<[String: CodexJSONValue], Error>?
    private var responseText = ""

    init(client: CodexAppServerClient) {
        self.client = client
    }

    var isActive: Bool {
        activeToken != nil
    }

    func generate(prompt: String, model: String, reasoningEffort: String?) async throws -> String {
        guard activeToken == nil else {
            throw AIError.requestFailed("Another ChatGPT generation is already in progress.")
        }

        let token = TurnToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeContinuation = continuation
                activeToken = token
                responseText = ""
                Task { [weak self] in
                    await self?.startTurn(
                        prompt: prompt,
                        model: model,
                        reasoningEffort: reasoningEffort,
                        token: token
                    )
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.interruptActiveTurn() }
        }
    }

    func reset() {
        interruptActiveTurn()
    }

    func handle(method: String, params: [String: CodexJSONValue]) {
        let threadID = params["threadId"]?.stringValue
        if let threadID, threadID == pendingInterruptThreadID, handlePendingInterrupt(method: method, params: params, threadID: threadID) {
            return
        }

        guard threadID == activeThreadID else { return }
        handleActiveTurn(method: method, params: params)
    }

    private func handlePendingInterrupt(
        method: String,
        params: [String: CodexJSONValue],
        threadID: String
    ) -> Bool {
        switch method {
        case "turn/started":
            if let turnID = params["turn"]?.objectValue?["id"]?.stringValue {
                pendingInterruptThreadID = nil
                interrupt(threadID: threadID, turnID: turnID)
            }
        case "turn/completed", "error":
            pendingInterruptThreadID = nil
        default:
            break
        }
        return true
    }

    private func handleActiveTurn(method: String, params: [String: CodexJSONValue]) {
        switch method {
        case "item/agentMessage/delta":
            responseText += params["delta"]?.stringValue ?? ""
        case "turn/started":
            activeTurnID = params["turn"]?.objectValue?["id"]?.stringValue
        case "turn/completed":
            let turn = params["turn"]?.objectValue
            switch turn?["status"]?.stringValue {
            case "completed":
                finish(.success(responseText))
            case "failed":
                finish(.failure(AIError.requestFailed(turn?["error"]?.objectValue?["message"]?.stringValue ?? "ChatGPT could not finish the response.")))
            default:
                finish(.failure(CancellationError()))
            }
        case "error":
            guard params["willRetry"]?.boolValue != true else { return }
            finish(.failure(AIError.requestFailed(params["error"]?.objectValue?["message"]?.stringValue ?? "ChatGPT returned an error.")))
        default:
            break
        }
    }

    private func startTurn(
        prompt: String,
        model: String,
        reasoningEffort: String?,
        token: TurnToken
    ) async {
        do {
            let models = try await connect?() ?? []
            try Task.checkCancellation()
            guard activeToken === token else { return }
            guard models.contains(where: { $0.id == model }) else {
                throw AIError.requestFailed("\(model) is no longer available in your ChatGPT subscription.")
            }

            let threadResponse = try await client.request(
                method: "thread/start",
                params: [
                    "model": model,
                    "cwd": client.workspace.path,
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "ephemeral": true,
                    "developerInstructions": Self.developerInstructions
                ]
            )
            guard activeToken === token,
                  let threadID = threadResponse["thread"]?.objectValue?["id"]?.stringValue else { return }
            activeThreadID = threadID

            var parameters: [String: Any] = [
                "threadId": threadID,
                "model": model,
                "approvalPolicy": "never",
                "sandboxPolicy": ["type": "readOnly", "networkAccess": false],
                "input": [["type": "text", "text": prompt]]
            ]
            if let reasoningEffort {
                parameters["effort"] = reasoningEffort
            }

            let task = Task { [client] in
                try await client.request(method: "turn/start", params: parameters)
            }
            turnStartTask = task
            let turnResponse = try await task.value
            turnStartTask = nil
            guard activeToken === token else { return }
            activeTurnID = turnResponse["turn"]?.objectValue?["id"]?.stringValue
        } catch is CancellationError {
            guard activeToken === token else { return }
            finish(.failure(CancellationError()))
        } catch {
            guard activeToken === token else { return }
            finish(.failure(error))
        }
    }

    private static let developerInstructions = """
    You are generating a Git commit message for GitMenuBar. Never invoke tools, execute commands, read files, inspect the environment, or modify files. Use only the request content supplied by GitMenuBar. Respond with the requested commit message only, in English.
    """

    private func interruptActiveTurn() {
        guard activeToken != nil else { return }
        let threadID = activeThreadID
        let turnID = activeTurnID
        turnStartTask?.cancel()
        turnStartTask = nil
        let continuation = activeContinuation
        activeContinuation = nil
        activeToken = nil
        activeThreadID = nil
        activeTurnID = nil
        responseText = ""
        continuation?.resume(throwing: CancellationError())
        onTurnEnded?()

        guard let threadID else { return }
        if let turnID {
            interrupt(threadID: threadID, turnID: turnID)
        } else {
            pendingInterruptThreadID = threadID
        }
    }

    private func interrupt(threadID: String, turnID: String) {
        Task { [weak self] in
            _ = try? await self?.client.request(
                method: "turn/interrupt",
                params: ["threadId": threadID, "turnId": turnID]
            )
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard activeToken != nil else { return }
        let continuation = activeContinuation
        activeContinuation = nil
        activeToken = nil
        activeThreadID = nil
        activeTurnID = nil
        turnStartTask = nil
        let response = responseText
        responseText = ""
        switch result {
        case .success:
            continuation?.resume(returning: response)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
        onTurnEnded?()
    }
}
