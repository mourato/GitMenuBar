import Foundation

struct ClaudeCodeUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .claudeCode

    private let homeDirectory: URL
    private let credentialsURL: URL
    private let keychainData: @Sendable () -> Data?
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let cookieSessionKey: @Sendable () -> String?
    private let cliSnapshot: @Sendable () async -> UsageQuotaSnapshot?

    private enum Constants {
        static let usageEndpoint = "https://api.anthropic.com/api/oauth/usage"
        static let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
        static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        static let keychainService = "Claude Code-credentials"
        static let oauthBeta = "oauth-2025-04-20"
        static let requestTimeout: TimeInterval = 10
    }

    private enum CredentialSource: Sendable {
        case file
        case keychain
    }

    private struct StoredCredentials: Sendable {
        let credentials: ClaudeCodeOAuthCredentials
        let source: CredentialSource
    }

    private enum UsageFetchResult: Sendable {
        case success(UsageQuotaSnapshot)
        case unauthorized
        case failed
    }

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        credentialsURL: URL? = nil,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        keychainData: (@Sendable () -> Data?)? = nil,
        cookieSessionKey: (@Sendable () -> String?)? = nil,
        cliSnapshot: (@Sendable () async -> UsageQuotaSnapshot?)? = nil
    ) {
        self.homeDirectory = homeDirectory
        let configuredDirectory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configDirectory = if let configuredDirectory, !configuredDirectory.isEmpty {
            URL(fileURLWithPath: configuredDirectory)
        } else {
            homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        }
        self.cookieSessionKey = cookieSessionKey ?? { ClaudeCodeCookieUsage.browserSessionKey() }
        self.cliSnapshot = cliSnapshot ?? {
            await ClaudeCodeCLIUsage.fetchSnapshot(homeDirectory: homeDirectory, now: now)
        }
        self.credentialsURL = credentialsURL ?? configDirectory.appendingPathComponent(".credentials.json")
        self.session = session
        self.now = now
        self.keychainData = keychainData ?? { Self.readKeychainData(service: Constants.keychainService) }
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        var hasCredentials = false
        if let storedCredentials = readCredentials() {
            hasCredentials = true
            var credentials = storedCredentials.credentials
            var attemptedRefresh = false

            if credentials.expiresAt.map({ now() >= $0 }) == true {
                attemptedRefresh = true
                if let refreshed = await refreshCredentials(storedCredentials) {
                    credentials = refreshed
                }
            }

            switch await fetchUsage(accessToken: credentials.accessToken) {
            case let .success(snapshot):
                return snapshot
            case .unauthorized where !attemptedRefresh:
                if let refreshed = await refreshCredentials(
                    StoredCredentials(credentials: credentials, source: storedCredentials.source)
                ),
                    case let .success(snapshot) = await fetchUsage(accessToken: refreshed.accessToken)
                {
                    return snapshot
                }
            case .unauthorized, .failed:
                break
            }
        }

        if let sessionKey = cookieSessionKey(),
           let cookieSnapshot = await ClaudeCodeCookieUsage.fetchSnapshot(
               sessionKey: sessionKey,
               session: session,
               now: now
           )
        {
            return cookieSnapshot
        }

        if let snapshot = await cliSnapshot() {
            return snapshot
        }

        if let localSnapshot = fetchLocalSnapshot() {
            return localSnapshot
        }

        return .unavailable(
            providerID: id,
            statusNote: hasCredentials ? "Claude Code usage unavailable" : "sign in to Claude Code"
        )
    }

    private func fetchUsage(accessToken: String) async -> UsageFetchResult {
        guard let url = URL(string: Constants.usageEndpoint) else { return .failed }

        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Constants.oauthBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli (external, cli)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else {
            return .failed
        }

        if http.statusCode == 401 {
            return .unauthorized
        }
        guard 200 ... 299 ~= http.statusCode,
              let snapshot = ClaudeCodeUsageParsing.snapshot(fromUsageAPI: data, now: now())
        else {
            return .failed
        }
        return .success(snapshot)
    }

    private func readCredentials() -> StoredCredentials? {
        if let data = try? Data(contentsOf: credentialsURL),
           let credentials = ClaudeCodeUsageParsing.credentials(fromCredentials: data)
        {
            return StoredCredentials(credentials: credentials, source: .file)
        }

        guard let data = keychainData() else { return nil }
        guard let credentials = ClaudeCodeUsageParsing.credentials(fromCredentials: data) else { return nil }
        return StoredCredentials(credentials: credentials, source: .keychain)
    }

    private func refreshCredentials(_ stored: StoredCredentials) async -> ClaudeCodeOAuthCredentials? {
        // Claude Code owns its keychain item. Refreshing would rotate the refresh token it holds,
        // so keychain credentials are only read; Claude Code refreshes them on its next run.
        guard stored.source == .file,
              let refreshToken = stored.credentials.refreshToken,
              let url = URL(string: Constants.tokenEndpoint)
        else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: Constants.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", Constants.oauthClientID)
        ])

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let tokenResponse = try? JSONDecoder().decode(TokenRefreshResponse.self, from: data),
              !tokenResponse.accessToken.isEmpty
        else {
            return nil
        }

        let nextRefreshToken = tokenResponse.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAt = now().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        let refreshed = ClaudeCodeOAuthCredentials(
            accessToken: tokenResponse.accessToken,
            refreshToken: nextRefreshToken.flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken,
            expiresAt: expiresAt
        )
        guard let persistedData = updatedCredentialsData(
            from: stored.credentials.rawData,
            credentials: refreshed
        ),
            persistCredentials(persistedData, source: stored.source)
        else {
            return nil
        }
        return ClaudeCodeOAuthCredentials(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt,
            rawData: persistedData
        )
    }

    private func updatedCredentialsData(
        from data: Data,
        credentials: ClaudeCodeOAuthCredentials
    ) -> Data? {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any],
              let expiresAt = credentials.expiresAt
        else {
            return nil
        }

        oauth["accessToken"] = credentials.accessToken
        if let refreshToken = credentials.refreshToken {
            oauth["refreshToken"] = refreshToken
        }
        oauth["expiresAt"] = expiresAt.timeIntervalSince1970 * 1000
        root["claudeAiOauth"] = oauth
        return try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func persistCredentials(_ data: Data, source: CredentialSource) -> Bool {
        source == .file && (try? data.write(to: credentialsURL, options: [.atomic])) != nil
    }

    private static func formBody(_ fields: [(String, String)]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func fetchLocalSnapshot() -> UsageQuotaSnapshot? {
        let projectsDirectory = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { modificationDate(for: $0) > modificationDate(for: $1) }

        for file in files.prefix(12) {
            guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { continue }
            let tail = data.count > 256_000 ? data.suffix(256_000) : data[...]
            guard let text = String(data: Data(tail), encoding: .utf8) else { continue }
            if let snapshot = ClaudeCodeUsageParsing.snapshot(fromJSONL: text) {
                return snapshot
            }
        }

        return nil
    }

    /// Reads through `/usr/bin/security`: Claude Code creates its item with that tool, so the item's
    /// access list already trusts it and no keychain prompt appears, unlike `SecItemCopyMatching`.
    private static func readKeychainData(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard let trimmed = String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return Data(trimmed.utf8)
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

private struct TokenRefreshResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
