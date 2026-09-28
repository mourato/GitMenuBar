import Foundation

#if os(macOS)
    import SweetCookieKit
#endif

enum ClaudeCodeCookieUsage {
    private static let organizationsURL = URL(string: "https://claude.ai/api/organizations")!
    private static let requestTimeout: TimeInterval = 10

    static func fetchSnapshot(
        sessionKey: String,
        session: URLSession,
        now: @escaping @Sendable () -> Date = Date.init
    ) async -> UsageQuotaSnapshot? {
        guard sessionKey.hasPrefix("sk-ant-") else { return nil }
        guard let organizationsData = await request(
            url: organizationsURL,
            sessionKey: sessionKey,
            session: session
        ),
            let organizations = try? JSONDecoder().decode([ClaudeCodeOrganization].self, from: organizationsData),
            let organization = organizations.first(where: { !$0.uuid.isEmpty })
        else {
            return nil
        }

        guard let usageURL = URL(string: "https://claude.ai/api/organizations/\(organization.uuid)/usage") else {
            return nil
        }
        guard let data = await request(url: usageURL, sessionKey: sessionKey, session: session) else {
            return nil
        }
        return ClaudeCodeUsageParsing.snapshot(
            fromUsageAPI: data,
            now: now(),
            statusNote: "Claude Code browser cookie usage API"
        )
    }

    #if os(macOS)
        static func browserSessionKey() -> String? {
            let client = BrowserCookieClient()
            let query = BrowserCookieQuery(domains: ["claude.ai"], domainMatch: .suffix)

            for browser in Browser.defaultImportOrder {
                guard !client.stores(for: browser).isEmpty,
                      let sources = try? client.records(matching: query, in: browser)
                else {
                    continue
                }

                for source in sources {
                    for record in source.records where record.name == "sessionKey" {
                        let value = record.value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if value.hasPrefix("sk-ant-") {
                            return value
                        }
                    }
                }
            }
            return nil
        }
    #else
        static func browserSessionKey() -> String? {
            nil
        }
    #endif

    private static func request(
        url: URL,
        sessionKey: String,
        session: URLSession
    ) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitMenuBar", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              200 ... 299 ~= http.statusCode
        else {
            return nil
        }
        return data
    }
}

private struct ClaudeCodeOrganization: Decodable {
    let uuid: String
}
