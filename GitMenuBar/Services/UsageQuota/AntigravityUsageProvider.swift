import Foundation

private struct AntigravityRemoteTokenRefreshResponse: Decodable {
    let accessToken: String?
    let expiresIn: Double?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
}

private final class AntigravityLocalhostSessionDelegate: NSObject, URLSessionDelegate {
    nonisolated func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == "127.0.0.1",
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

final class AntigravityUsageProvider: UsageQuotaProviding, Sendable {
    let id: UsageProviderID = .antigravity

    private static let getUserStatusPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"
    private static let quotaSummaryPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    private static let commandModelConfigPath = "/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs"
    private static let retrieveUserQuotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private static let loadCodeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
    private static let tokenRefreshEndpoint = "https://oauth2.googleapis.com/token"

    struct Configuration: Sendable {
        let timeout: TimeInterval
        let remoteCredentialsURL: URL

        init(
            timeout: TimeInterval = 4.0,
            remoteCredentialsURL: URL? = nil
        ) {
            self.timeout = timeout
            self.remoteCredentialsURL = remoteCredentialsURL ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codexbar/antigravity/oauth_creds.json")
        }
    }

    private struct LocalEndpoint {
        let scheme: String
        let port: Int
        let csrfToken: String?
    }

    private let configuration: Configuration
    private let session: URLSession
    private let processDetector: @Sendable () -> [AntigravityProcessDetector.DetectedServer]
    private let now: @Sendable () -> Date

    init(
        configuration: Configuration = Configuration(),
        session: URLSession? = nil,
        processDetector: @escaping @Sendable () -> [AntigravityProcessDetector.DetectedServer] = {
            AntigravityProcessDetector.detectRunningServers()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.session = session ?? URLSession(
            configuration: .ephemeral,
            delegate: AntigravityLocalhostSessionDelegate(),
            delegateQueue: nil
        )
        self.processDetector = processDetector
        self.now = now
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        for server in processDetector() {
            if let snapshot = await probeLocalServer(server) {
                return snapshot
            }
        }

        if let remoteSnapshot = await fetchRemoteSnapshot() {
            return remoteSnapshot
        }

        return .unavailable(providerID: .antigravity, statusNote: "sign in to Antigravity")
    }

    private func probeLocalServer(_ server: AntigravityProcessDetector.DetectedServer) async -> UsageQuotaSnapshot? {
        if let quotas = await requestLocalEndpoint(
            server: server,
            path: Self.quotaSummaryPath,
            body: Data(#"{"forceRefresh":true}"#.utf8),
            parser: AntigravityUsageParsing.parseQuotaSummaryResponse
        ) {
            return AntigravityUsageParsing.snapshot(from: quotas, now: now())
        }

        if let quotas = await requestLocalEndpoint(
            server: server,
            path: Self.getUserStatusPath,
            parser: AntigravityUsageParsing.parseUserStatusResponse
        ) {
            return AntigravityUsageParsing.snapshot(from: quotas, now: now())
        }

        if let quotas = await requestLocalEndpoint(
            server: server,
            path: Self.commandModelConfigPath,
            parser: AntigravityUsageParsing.parseCommandModelConfigResponse
        ) {
            return AntigravityUsageParsing.snapshot(from: quotas, now: now())
        }

        return nil
    }

    private func requestLocalEndpoint(
        server: AntigravityProcessDetector.DetectedServer,
        path: String,
        body: Data = Data("{}".utf8),
        parser: (Data) throws -> [AntigravityUsageParsing.ModelQuota]
    ) async -> [AntigravityUsageParsing.ModelQuota]? {
        var endpoints = [LocalEndpoint(scheme: "https", port: server.port, csrfToken: server.csrfToken)]
        if let extensionPort = server.extensionPort {
            endpoints.append(LocalEndpoint(
                scheme: "http",
                port: extensionPort,
                csrfToken: server.extensionCSRFToken ?? server.csrfToken
            ))
        }

        for endpoint in endpoints {
            guard let url = URL(string: "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)\(path)") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = configuration.timeout
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            if let token = endpoint.csrfToken, !token.isEmpty {
                request.setValue(token, forHTTPHeaderField: "X-Codeium-Csrf-Token")
            }

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let quotas = try? parser(data),
                  quotas.contains(where: { !$0.isDisabled })
            else {
                continue
            }
            return quotas
        }
        return nil
    }

    private func fetchRemoteSnapshot() async -> UsageQuotaSnapshot? {
        guard let data = try? Data(contentsOf: configuration.remoteCredentialsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var accessToken = stringValue(in: json, keys: ["access_token", "accessToken"]),
              !accessToken.isEmpty
        else {
            return nil
        }

        if let expiryDate = dateValue(in: json, keys: ["expiry_date", "expiryDate"]),
           expiryDate <= now().addingTimeInterval(300)
        {
            guard let refreshToken = stringValue(in: json, keys: ["refresh_token", "refreshToken"]),
                  let refreshed = await refreshAccessToken(refreshToken: refreshToken, credentials: json)
            else { return nil }
            accessToken = refreshed.accessToken ?? accessToken
            persist(refreshed)
        }

        let storedProjectId = stringValue(in: json, keys: ["project_id", "projectId"])
        let projectId: String? = if let storedProjectId {
            storedProjectId
        } else {
            await loadProjectId(accessToken: accessToken)
        }
        if storedProjectId == nil, let projectId {
            persist(projectId: projectId)
        }
        guard let url = URL(string: Self.retrieveUserQuotaEndpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: projectId.map { ["project": $0] } ?? [:])

        guard let (responseData, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let quotas = try? AntigravityUsageParsing.parseRemoteQuotaResponse(responseData),
              quotas.contains(where: { !$0.isDisabled })
        else {
            return nil
        }

        return AntigravityUsageParsing.snapshot(from: quotas, now: now())
    }

    private func loadProjectId(accessToken: String) async -> String? {
        guard let url = URL(string: Self.loadCodeAssistEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ])

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let project = json["cloudaicompanionProject"] as? String {
            return project.nonEmptyTrimmed
        }
        if let project = json["cloudaicompanionProject"] as? [String: Any] {
            return (project["id"] as? String)?.nonEmptyTrimmed
                ?? (project["projectId"] as? String)?.nonEmptyTrimmed
        }
        return (json["projectId"] as? String)?.nonEmptyTrimmed
    }

    private func refreshAccessToken(
        refreshToken: String,
        credentials: [String: Any]
    ) async -> AntigravityRemoteTokenRefreshResponse? {
        guard let client = resolveOAuthClient(credentials: credentials),
              let url = URL(string: Self.tokenRefreshEndpoint)
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "client_id": client.id,
            "client_secret": client.secret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let refreshed = try? JSONDecoder().decode(AntigravityRemoteTokenRefreshResponse.self, from: data),
              let accessToken = refreshed.accessToken,
              !accessToken.isEmpty
        else { return nil }
        return refreshed
    }

    private func resolveOAuthClient(credentials: [String: Any]) -> (id: String, secret: String)? {
        let environment = ProcessInfo.processInfo.environment
        let id = environment["ANTIGRAVITY_OAUTH_CLIENT_ID"]
            ?? environment["GEMINI_OAUTH_CLIENT_ID"]
            ?? stringValue(in: credentials, keys: ["client_id", "clientId"])
        let secret = environment["ANTIGRAVITY_OAUTH_CLIENT_SECRET"]
            ?? environment["GEMINI_OAUTH_CLIENT_SECRET"]
            ?? stringValue(in: credentials, keys: ["client_secret", "clientSecret"])
        if let id, let secret, !id.isEmpty, !secret.isEmpty {
            return (id, secret)
        }

        return discoverInstalledOAuthClient()
    }

    private func persist(_ refreshed: AntigravityRemoteTokenRefreshResponse) {
        guard let accessToken = refreshed.accessToken,
              let data = try? Data(contentsOf: configuration.remoteCredentialsURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        json["access_token"] = accessToken
        if let expiresIn = refreshed.expiresIn {
            json["expiry_date"] = (now().timeIntervalSince1970 + expiresIn) * 1000
        }
        if let idToken = refreshed.idToken {
            json["id_token"] = idToken
        }
        guard let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else {
            return
        }
        try? updated.write(to: configuration.remoteCredentialsURL, options: .atomic)
    }

    private func persist(projectId: String) {
        guard let data = try? Data(contentsOf: configuration.remoteCredentialsURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        json["project_id"] = projectId
        guard let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else {
            return
        }
        try? updated.write(to: configuration.remoteCredentialsURL, options: .atomic)
    }

    private func discoverInstalledOAuthClient() -> (id: String, secret: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [
            "/Applications/Antigravity.app",
            "\(home)/Applications/Antigravity.app"
        ]
        let relativePaths = [
            "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm",
            "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_x64",
            "Contents/Resources/app/out/main.js",
            "Contents/MacOS/Antigravity"
        ]

        for root in roots {
            for relativePath in relativePaths {
                let path = "\(root)/\(relativePath)"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
                guard let text = String(data: data, encoding: .utf8) else { continue }
                guard let id = firstMatch(
                    pattern: #"[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com"#,
                    in: text
                ),
                    let secret = firstMatch(pattern: #"GOCSPX-[A-Za-z0-9_-]+"#, in: text)
                else { continue }
                return (id, secret)
            }
        }
        return nil
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }

    private func stringValue(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = (json[key] as? String)?.nonEmptyTrimmed {
                return value
            }
        }
        return nil
    }

    private func dateValue(in json: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let number = json[key] as? NSNumber {
                let value = number.doubleValue
                return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
            }
            if let string = json[key] as? String, let value = Double(string) {
                return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
            }
        }
        return nil
    }

    private func formEncoded(_ values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
