import Foundation

/// Compatibility adapter for the existing settings surface; it delegates to the shared blob.
protocol OpenRouterAPIKeyStoring: Sendable {
    func loadKey() -> String?
    func saveKey(_ apiKey: String)
    func deleteKey()
}

struct OpenRouterAPIKeyStore: OpenRouterAPIKeyStoring {
    private let store: any AIAPIKeyStore

    init(store: any AIAPIKeyStore = CachedAIAPIKeyStore.shared) {
        self.store = store
    }

    func loadKey() -> String? {
        try? store.apiKey(for: .openrouter)
    }

    func saveKey(_ apiKey: String) {
        try? store.saveAPIKey(apiKey, for: .openrouter)
    }

    func deleteKey() {
        try? store.deleteAPIKey(for: .openrouter)
    }
}

final class InMemoryOpenRouterAPIKeyStore: OpenRouterAPIKeyStoring, @unchecked Sendable {
    private let store = InMemoryAIAPIKeyStore()
    func loadKey() -> String? {
        try? store.apiKey(for: .openrouter)
    }

    func saveKey(_ apiKey: String) {
        try? store.saveAPIKey(apiKey, for: .openrouter)
    }

    func deleteKey() {
        try? store.deleteAPIKey(for: .openrouter)
    }
}

struct OpenRouterUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .openrouter

    private let urlSession: URLSession
    private let keyStore: any AIAPIKeyStore
    private let stateStore: OpenRouterUsageStateStore

    init(
        urlSession: URLSession = .shared,
        keyStore: any AIAPIKeyStore = AIKeychainStore(),
        stateStore: OpenRouterUsageStateStore = OpenRouterUsageStateStore()
    ) {
        self.urlSession = urlSession
        self.keyStore = keyStore
        self.stateStore = stateStore
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        let apiKey: String
        do {
            guard let storedKey = try keyStore.apiKey(for: .openrouter), !storedKey.isEmpty else {
                return .unavailable(providerID: .openrouter, statusNote: "add OpenRouter API key in Settings")
            }
            apiKey = storedKey
        } catch {
            return .unavailable(providerID: .openrouter, statusNote: "OpenRouter credential unavailable")
        }
        if apiKey.isEmpty {
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
