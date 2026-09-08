import Foundation

final class AntigravityUsageProvider: UsageQuotaProviding, Sendable {
    let id: UsageProviderID = .antigravity

    private static let getUserStatusPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"
    private static let quotaSummaryPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    private static let retrieveUserQuotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private static let loadCodeAssistEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"

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

    private let configuration: Configuration
    private let session: URLSession
    private let processDetector: @Sendable () -> [AntigravityProcessDetector.DetectedServer]
    private let now: @Sendable () -> Date

    init(
        configuration: Configuration = Configuration(),
        session: URLSession = .shared,
        processDetector: @escaping @Sendable () -> [AntigravityProcessDetector.DetectedServer] = {
            AntigravityProcessDetector.detectRunningServers()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.session = session
        self.processDetector = processDetector
        self.now = now
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        // 1. Try local detected servers first
        let servers = processDetector()
        for server in servers {
            if let snapshot = await probeLocalServer(server) {
                return snapshot
            }
        }

        // 2. Try remote credentials if available
        if let remoteSnapshot = await fetchRemoteSnapshot() {
            return remoteSnapshot
        }

        return .unavailable(providerID: .antigravity, statusNote: "sign in to Antigravity")
    }

    private func probeLocalServer(_ server: AntigravityProcessDetector.DetectedServer) async -> UsageQuotaSnapshot? {
        // Try GetUserStatus first
        if let quotas = await requestLocalEndpoint(server: server, path: Self.getUserStatusPath, parser: AntigravityUsageParsing.parseUserStatusResponse),
           !quotas.isEmpty
        {
            return AntigravityUsageParsing.snapshot(from: quotas, now: now())
        }

        // Try RetrieveUserQuotaSummary
        if let quotas = await requestLocalEndpoint(server: server, path: Self.quotaSummaryPath, parser: AntigravityUsageParsing.parseQuotaSummaryResponse),
           !quotas.isEmpty
        {
            return AntigravityUsageParsing.snapshot(from: quotas, now: now())
        }

        return nil
    }

    private func requestLocalEndpoint(
        server: AntigravityProcessDetector.DetectedServer,
        path: String,
        parser: (Data) throws -> [AntigravityUsageParsing.ModelQuota]
    ) async -> [AntigravityUsageParsing.ModelQuota]? {
        guard let url = URL(string: "http://127.0.0.1:\(server.port)\(path)") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)

        if let token = server.csrfToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            return nil
        }

        return try? parser(data)
    }

    private func fetchRemoteSnapshot() async -> UsageQuotaSnapshot? {
        guard FileManager.default.fileExists(atPath: configuration.remoteCredentialsURL.path),
              let data = try? Data(contentsOf: configuration.remoteCredentialsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = (json["access_token"] as? String ?? json["accessToken"] as? String),
              !accessToken.isEmpty
        else {
            return nil
        }

        guard let url = URL(string: Self.retrieveUserQuotaEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        guard let (respData, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let quotas = try? AntigravityUsageParsing.parseRemoteQuotaResponse(respData),
              !quotas.isEmpty
        else {
            return nil
        }

        return AntigravityUsageParsing.snapshot(from: quotas, now: now())
    }
}
