import Foundation

private struct GeminiCredentialsFile: Codable {
    let accessToken: String?
    let refreshToken: String?
    let expiryDate: Double?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiryDate = "expiry_date"
        case idToken = "id_token"
    }

    func isExpired(at now: Date, safetyWindow: TimeInterval = 300) -> Bool {
        guard let expiryDate else { return false }
        // expiryDate in ~/.gemini/oauth_creds.json is either ms or seconds
        let seconds = expiryDate > 10_000_000_000 ? expiryDate / 1000 : expiryDate
        return Date(timeIntervalSince1970: seconds) <= now.addingTimeInterval(safetyWindow)
    }
}

private struct GeminiTokenRefreshResponse: Decodable {
    let accessToken: String?
    let expiresIn: Double?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
}

private struct GeminiOAuthClient {
    let id: String
    let secret: String
}

final class GeminiUsageProvider: UsageQuotaProviding, Sendable {
    let id: UsageProviderID = .gemini

    private static let loadCodeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
    private static let retrieveUserQuotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private static let projectsEndpoint = "https://cloudresourcemanager.googleapis.com/v1/projects"
    private static let tokenRefreshEndpoint = "https://oauth2.googleapis.com/token"

    struct Configuration: Sendable {
        let credentialsURL: URL
        let timeout: TimeInterval

        init(
            credentialsURL: URL? = nil,
            timeout: TimeInterval = 10.0
        ) {
            self.credentialsURL = credentialsURL ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gemini/oauth_creds.json")
            self.timeout = timeout
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(
        configuration: Configuration = Configuration(),
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.session = session
        self.now = now
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        guard FileManager.default.fileExists(atPath: configuration.credentialsURL.path) else {
            return .unavailable(providerID: .gemini, statusNote: "sign in to Gemini CLI")
        }

        guard let data = try? Data(contentsOf: configuration.credentialsURL),
              let creds = try? JSONDecoder().decode(GeminiCredentialsFile.self, from: data)
        else {
            return .unavailable(providerID: .gemini, statusNote: "invalid Gemini credentials")
        }

        var accessToken = creds.accessToken
        if creds.isExpired(at: now()) || accessToken == nil || accessToken?.isEmpty == true {
            if let refreshed = await refreshAccessToken(refreshToken: creds.refreshToken) {
                accessToken = refreshed.accessToken
                persist(refreshed)
            } else if accessToken == nil || accessToken?.isEmpty == true {
                return .unavailable(providerID: .gemini, statusNote: "token expired — open Gemini")
            }
        }

        guard let activeToken = accessToken, !activeToken.isEmpty else {
            return .unavailable(providerID: .gemini, statusNote: "token expired — open Gemini")
        }

        do {
            let projectId: String? = if let loadedProjectId = await loadProjectId(accessToken: activeToken) {
                loadedProjectId
            } else {
                await discoverProjectId(accessToken: activeToken)
            }
            let quotas = try await requestQuota(accessToken: activeToken, projectId: projectId)
            return GeminiUsageParsing.snapshot(from: quotas, now: now())
        } catch let error as URLError where error.code == .cancelled {
            return .unavailable(providerID: .gemini, statusNote: "request cancelled")
        } catch let error as NSError where error.domain == "GeminiHTTP" && error.code == 401 {
            return .unavailable(providerID: .gemini, statusNote: "token expired — open Gemini")
        } catch {
            return .unavailable(providerID: .gemini, statusNote: "connection error")
        }
    }

    private func loadProjectId(accessToken: String) async -> String? {
        guard let url = URL(string: Self.loadCodeAssistEndpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "metadata": [
                "ideType": "GEMINI_CLI",
                "pluginType": "GEMINI"
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let project = json["cloudaicompanionProject"] as? String {
            return project.nonEmptyTrimmed
        }
        if let project = json["cloudaicompanionProject"] as? [String: Any] {
            return (project["id"] as? String)?.nonEmptyTrimmed
                ?? (project["projectId"] as? String)?.nonEmptyTrimmed
        }
        return (json["projectId"] as? String)?.nonEmptyTrimmed
    }

    private func discoverProjectId(accessToken: String) async -> String? {
        // Cloud Resource Manager is only a fallback for accounts where
        // loadCodeAssist does not return the managed Gemini project.
        guard let url = URL(string: Self.projectsEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [[String: Any]]
        else { return nil }

        let candidates = projects.compactMap { project -> (String, Bool)? in
            guard let id = (project["projectId"] as? String)?.nonEmptyTrimmed else { return nil }
            let labels = project["labels"] as? [String: String] ?? [:]
            return (id, id.hasPrefix("gen-lang-client") || labels["generative-language"] != nil)
        }
        return candidates.first(where: { $0.1 })?.0 ?? candidates.first?.0
    }

    private func requestQuota(accessToken: String, projectId: String?) async throws -> [GeminiUsageParsing.ModelQuota] {
        guard let url = URL(string: Self.retrieveUserQuotaEndpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = if let projectId, !projectId.isEmpty {
            ["project": projectId]
        } else {
            [:]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            throw NSError(domain: "GeminiHTTP", code: http.statusCode)
        }

        return try GeminiUsageParsing.parseAPIResponse(data)
    }

    private func refreshAccessToken(refreshToken: String?) async -> GeminiTokenRefreshResponse? {
        guard let refreshToken, !refreshToken.isEmpty else { return nil }

        guard let client = resolveOAuthClient() else { return nil }

        guard let url = URL(string: Self.tokenRefreshEndpoint) else { return nil }

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
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            return nil
        }

        guard let response = try? JSONDecoder().decode(GeminiTokenRefreshResponse.self, from: data),
              let accessToken = response.accessToken,
              !accessToken.isEmpty
        else { return nil }
        return response
    }

    private func persist(_ refreshed: GeminiTokenRefreshResponse) {
        guard let accessToken = refreshed.accessToken,
              let data = try? Data(contentsOf: configuration.credentialsURL),
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
        try? updated.write(to: configuration.credentialsURL, options: .atomic)
    }

    private func resolveOAuthClient() -> GeminiOAuthClient? {
        let environment = ProcessInfo.processInfo.environment
        if let id = environment["GEMINI_OAUTH_CLIENT_ID"],
           let secret = environment["GEMINI_OAUTH_CLIENT_SECRET"],
           !id.isEmpty, !secret.isEmpty
        {
            return GeminiOAuthClient(id: id, secret: secret)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let oauthRelativePath = "dist/src/code_assist/oauth2.js"
        var paths = [
            "/opt/homebrew/lib/node_modules/@google/gemini-cli-core/\(oauthRelativePath)",
            "/usr/local/lib/node_modules/@google/gemini-cli-core/\(oauthRelativePath)",
            "\(home)/.npm-global/lib/node_modules/@google/gemini-cli-core/\(oauthRelativePath)"
        ]

        for prefix in ["/opt/homebrew", "/usr/local"] {
            let optRoot = "\(prefix)/opt/gemini-cli/libexec/lib/node_modules/@google/gemini-cli"
            paths.append("\(optRoot)/\(oauthRelativePath)")
            let cellarRoot = "\(prefix)/Cellar/gemini-cli"
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: cellarRoot) {
                paths.append(contentsOf: versions.map {
                    "\(cellarRoot)/\($0)/libexec/lib/node_modules/@google/gemini-cli/\(oauthRelativePath)"
                })
            }
        }

        for path in paths {
            guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let id = matchOAuthValue(named: "OAUTH_CLIENT_ID", in: source)
            let secret = matchOAuthValue(named: "OAUTH_CLIENT_SECRET", in: source)
            if let id, let secret {
                return GeminiOAuthClient(id: id, secret: secret)
            }
        }
        return nil
    }

    private func matchOAuthValue(named name: String, in source: String) -> String? {
        let pattern = #"(?:const|let|var)?\s*\#(name)\s*=\s*['"]([\w\-.]+)['"]\s*;"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source)
        else { return nil }
        return String(source[range])
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
