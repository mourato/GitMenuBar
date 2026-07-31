import Foundation

struct OpenRouterUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .openrouter

    private let urlSession: URLSession
    private let keyStore: any OpenRouterAPIKeyStoring

    init(
        urlSession: URLSession = .shared,
        keyStore: any OpenRouterAPIKeyStoring = OpenRouterAPIKeyStore()
    ) {
        self.urlSession = urlSession
        self.keyStore = keyStore
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        guard let apiKey = keyStore.loadKey(), !apiKey.isEmpty else {
            return .unavailable(providerID: .openrouter, statusNote: "add OpenRouter API key in Settings")
        }

        var request = URLRequest(
            url: URL(string: "https://openrouter.ai/api/v1/credits")!,
            timeoutInterval: 10
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitMenuBar", forHTTPHeaderField: "User-Agent")
        request.setValue("GitMenuBar", forHTTPHeaderField: "X-Title")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard (response as? HTTPURLResponse).map({ 200 ... 299 ~= $0.statusCode }) == true,
                  let snapshot = OpenRouterUsageParsing.snapshot(fromCreditsData: data) else {
                return .unavailable(providerID: .openrouter, statusNote: "openrouter credits unavailable")
            }
            return snapshot
        } catch {
            return .unavailable(providerID: .openrouter, statusNote: "openrouter credits unavailable")
        }
    }
}
