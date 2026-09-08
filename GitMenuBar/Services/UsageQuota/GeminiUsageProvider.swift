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

    var isExpired: Bool {
        guard let expiryDate else { return false }
        // expiryDate in ~/.gemini/oauth_creds.json is either ms or seconds
        let seconds = expiryDate > 10_000_000_000 ? expiryDate / 1000 : expiryDate
        return Date(timeIntervalSince1970: seconds) <= Date()
    }
}

private struct GeminiCodeAssistResponse: Decodable {
    let projectId: String?
}

private struct GeminiTokenRefreshResponse: Decodable {
    let accessToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

final class GeminiUsageProvider: UsageQuotaProviding, Sendable {
    let id: UsageProviderID = .gemini

    private static let loadCodeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
    private static let retrieveUserQuotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
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
        if creds.isExpired || accessToken == nil || accessToken?.isEmpty == true {
            if let refreshedToken = await refreshAccessToken(refreshToken: creds.refreshToken) {
                accessToken = refreshedToken
            } else if accessToken == nil || accessToken?.isEmpty == true {
                return .unavailable(providerID: .gemini, statusNote: "token expired — open Gemini")
            }
        }

        guard let activeToken = accessToken, !activeToken.isEmpty else {
            return .unavailable(providerID: .gemini, statusNote: "token expired — open Gemini")
        }

        do {
            let projectId = await loadProjectId(accessToken: activeToken)
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
                "ideType": "GEMINI",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            return nil
        }

        let decoded = try? JSONDecoder().decode(GeminiCodeAssistResponse.self, from: data)
        return decoded?.projectId
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

    private func refreshAccessToken(refreshToken: String?) async -> String? {
        guard let refreshToken, !refreshToken.isEmpty else { return nil }

        let env = ProcessInfo.processInfo.environment
        guard let clientID = env["GEMINI_OAUTH_CLIENT_ID"],
              let clientSecret = env["GEMINI_OAUTH_CLIENT_SECRET"]
        else {
            return nil
        }

        guard let url = URL(string: Self.tokenRefreshEndpoint) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            return nil
        }

        let decoded = try? JSONDecoder().decode(GeminiTokenRefreshResponse.self, from: data)
        return decoded?.accessToken
    }
}
