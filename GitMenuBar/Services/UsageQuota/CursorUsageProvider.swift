import Foundation

struct CursorUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .cursor

    private let urlSession: URLSession
    private let tokenConfiguration: CursorAuthTokenReader.Configuration

    init(
        urlSession: URLSession = .shared,
        tokenConfiguration: CursorAuthTokenReader.Configuration = CursorAuthTokenReader.Configuration()
    ) {
        self.urlSession = urlSession
        self.tokenConfiguration = tokenConfiguration
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        guard let accessToken = CursorAuthTokenReader.readAccessToken(configuration: tokenConfiguration) else {
            return .unavailable(providerID: .cursor, statusNote: "sign in to Cursor")
        }

        guard let cookieValue = CursorUsageParsing.sessionCookieValue(accessToken: accessToken) else {
            return .unavailable(providerID: .cursor, statusNote: "token expired — open Cursor")
        }

        // Unofficial Cursor dashboard endpoint; schema and auth may break without notice.
        // GET https://cursor.com/api/usage-summary
        var request = URLRequest(
            url: URL(string: "https://cursor.com/api/usage-summary")!,
            timeoutInterval: 10
        )
        request.httpMethod = "GET"
        request.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitMenuBar", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard (response as? HTTPURLResponse).map({ 200 ... 299 ~= $0.statusCode }) == true,
                  let snapshot = CursorUsageParsing.snapshot(fromUsageSummary: data)
            else {
                return .unavailable(providerID: .cursor, statusNote: "usage unavailable")
            }
            return snapshot
        } catch {
            return .unavailable(providerID: .cursor, statusNote: "usage unavailable")
        }
    }
}
