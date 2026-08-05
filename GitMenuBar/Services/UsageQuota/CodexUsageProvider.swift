import Foundation

private struct CodexAuthState {
    let auth: [String: Any]
}

struct CodexUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .codex

    private let urlSession: URLSession
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        urlSession: URLSession = .shared,
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) {
        self.urlSession = urlSession
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        if let apiSnapshot = await fetchFromUsageAPI() {
            return apiSnapshot
        }

        if let localSnapshot = fetchFromLocalSessions() {
            return localSnapshot
        }

        if readCodexAuthState() == nil {
            return .unavailable(providerID: .codex, statusNote: "sign in to Codex")
        }

        return .unavailable(providerID: .codex, statusNote: "token expired — open Codex")
    }

    private func fetchFromUsageAPI() async -> UsageQuotaSnapshot? {
        guard let authState = readCodexAuthState(),
              let accessToken = await resolveAccessToken(authState: authState)
        else {
            return nil
        }

        if let snapshot = await requestUsageAPI(accessToken: accessToken, auth: authState.auth) {
            return snapshot
        }

        guard let refreshedToken = await refreshAccessTokenInMemory(authState: authState) else {
            return nil
        }

        return await requestUsageAPI(accessToken: refreshedToken, auth: authState.auth)
    }

    private func fetchFromLocalSessions() -> UsageQuotaSnapshot? {
        let sessionsDirectory = homeDirectory.appendingPathComponent(".codex/sessions")
        guard let file = CodexUsageParsing.latestJSONLFile(in: sessionsDirectory, fileManager: fileManager),
              let text = try? String(contentsOf: file, encoding: .utf8)
        else {
            return nil
        }
        return CodexUsageParsing.snapshot(fromSessionsJSONL: text)
    }

    private func readCodexAuthState() -> CodexAuthState? {
        var paths: [URL] = []
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !codexHome.isEmpty
        {
            paths.append(URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json"))
        }
        paths.append(homeDirectory.appendingPathComponent(".codex/auth.json"))
        paths.append(homeDirectory.appendingPathComponent(".config/codex/auth.json"))

        for path in paths {
            guard let data = try? Data(contentsOf: path),
                  let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  CodexUsageParsing.codexAccessToken(in: auth) != nil
                  || CodexUsageParsing.codexRefreshToken(in: auth) != nil
            else {
                continue
            }
            return CodexAuthState(auth: auth)
        }
        return nil
    }

    private func resolveAccessToken(authState: CodexAuthState) async -> String? {
        guard let accessToken = CodexUsageParsing.codexAccessToken(in: authState.auth) else {
            return await refreshAccessTokenInMemory(authState: authState)
        }

        if let expiresAt = CodexUsageParsing.jwtExpiry(accessToken),
           expiresAt.timeIntervalSinceNow <= 300
        {
            return await refreshAccessTokenInMemory(authState: authState) ?? accessToken
        }
        return accessToken
    }

    private func refreshAccessTokenInMemory(authState: CodexAuthState) async -> String? {
        guard let refreshToken = CodexUsageParsing.codexRefreshToken(in: authState.auth) else {
            return CodexUsageParsing.codexAccessToken(in: authState.auth)
        }

        var request = URLRequest(
            url: URL(string: "https://auth.openai.com/oauth/token")!,
            timeoutInterval: 10
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "refresh_token": refreshToken
        ]
        .map { "\($0.key)=\(CodexUsageParsing.urlEncode($0.value))" }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard (response as? HTTPURLResponse).map({ 200 ... 299 ~= $0.statusCode }) == true,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = root["access_token"] as? String,
                  !accessToken.isEmpty
            else {
                return CodexUsageParsing.codexAccessToken(in: authState.auth)
            }
            return accessToken
        } catch {
            return CodexUsageParsing.codexAccessToken(in: authState.auth)
        }
    }

    private func requestUsageAPI(accessToken: String, auth: [String: Any]) async -> UsageQuotaSnapshot? {
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            timeoutInterval: 10
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitMenuBar", forHTTPHeaderField: "User-Agent")
        if let accountID = CodexUsageParsing.codexAccountID(from: auth), !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard (response as? HTTPURLResponse).map({ 200 ... 299 ~= $0.statusCode }) == true,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var snapshot = CodexUsageParsing.snapshot(fromUsageAPI: root)
            else {
                return nil
            }

            if let resetCredits = await fetchResetCreditsAvailable(
                accessToken: accessToken,
                accountID: CodexUsageParsing.codexAccountID(from: auth)
            ) {
                snapshot = snapshot.withResetCreditsAvailable(resetCredits)
            }
            return snapshot
        } catch {
            return nil
        }
    }

    private func fetchResetCreditsAvailable(accessToken: String, accountID: String?) async -> Int? {
        // Unofficial ChatGPT endpoint used by CodexBar; may break without notice.
        // GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
            timeoutInterval: 4
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitMenuBar", forHTTPHeaderField: "User-Agent")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard (response as? HTTPURLResponse).map({ 200 ... 299 ~= $0.statusCode }) == true else {
                return nil
            }
            return CodexUsageParsing.resetCreditsAvailable(from: data)
        } catch {
            return nil
        }
    }
}
