import Foundation

struct OpenRouterUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .openrouter

    private let urlSession: URLSession
    private let keyStore: any OpenRouterAPIKeyStoring
    private let stateStore: OpenRouterUsageStateStore

    init(
        urlSession: URLSession = .shared,
        keyStore: any OpenRouterAPIKeyStoring = OpenRouterAPIKeyStore(),
        stateStore: OpenRouterUsageStateStore = OpenRouterUsageStateStore()
    ) {
        self.urlSession = urlSession
        self.keyStore = keyStore
        self.stateStore = stateStore
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
                  let parsed = OpenRouterUsageParsing.parse(
                      fromCreditsData: data,
                      previousState: stateStore.load()
                  ) else {
                return .unavailable(providerID: .openrouter, statusNote: "openrouter credits unavailable")
            }
            stateStore.save(parsed.state)
            return parsed.snapshot
        } catch {
            return .unavailable(providerID: .openrouter, statusNote: "openrouter credits unavailable")
        }
    }
}
