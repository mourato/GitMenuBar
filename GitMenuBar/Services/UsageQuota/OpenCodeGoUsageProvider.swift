import Foundation

/// OpenCode Go quota provider (Fase 1: API autoritativa + estimativa local).
///
/// Estratégias portadas do CodexBar (MIT, steipete), adaptadas ao modelo do
/// GitMenuBar:
/// - API: `GET https://opencode.ai/zen/go/v1/usage` com `Bearer OPENCODE_API_KEY`
///   (Keychain `opencodego` primeiro, ambiente depois). Janelas 5h/semanal/mensal.
/// - Local: agregação somente-leitura de `opencode.db` com os denominadores
///   fixos $12/$30/$60 e status "local estimate — not account quota".
/// Fora do escopo Fase 1: cookies web/console, login CLI, Zen balance e
/// histórico diário de custos.
struct OpenCodeGoUsageProvider: UsageQuotaProviding {
    let id: UsageProviderID = .opencodeGo

    private let urlSession: URLSession
    private let keyStore: (any AIAPIKeyStore)?
    private let environment: [String: String]
    private let homeDirectory: URL
    private let now: @Sendable () -> Date

    init(
        urlSession: URLSession = .shared,
        keyStore: (any AIAPIKeyStore)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.urlSession = urlSession
        self.keyStore = keyStore
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.now = now
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        let apiKey = resolveAPIKey()
        if let apiKey {
            do {
                return try await fetchAPIUsage(apiKey: apiKey)
            } catch let error as OpenCodeGoAPIError {
                switch error {
                case .invalidCredentials:
                    // Chave configurada rejeitada: erro explícito, sem mascarar
                    // com estimativa local de outra conta.
                    return .unavailable(providerID: .opencodeGo, statusNote: "token expired — open OpenCode")
                case .unavailable:
                    break
                }
            } catch {
                // Queda para a estimativa local abaixo.
            }
        }

        if let local = OpenCodeGoLocalUsage.snapshot(
            homeDirectory: homeDirectory,
            environment: environment,
            now: now()
        ) {
            return local
        }

        if apiKey != nil {
            return .unavailable(providerID: .opencodeGo, statusNote: "opencode go usage unavailable")
        }
        return .unavailable(providerID: .opencodeGo, statusNote: "sign in to OpenCode Go")
    }

    private func resolveAPIKey() -> String? {
        if let stored = try? keyStore?.apiKey(for: .opencodego),
           let cleaned = cleanedKey(stored)
        {
            return cleaned
        }
        // Produção usa o Keychain compartilhado; sem injeção, cai no ambiente.
        if keyStore == nil,
           let stored = try? AIKeychainStore().apiKey(for: .opencodego),
           let cleaned = cleanedKey(stored)
        {
            return cleaned
        }
        return cleanedKey(environment["OPENCODE_API_KEY"])
    }

    private func cleanedKey(_ raw: String?) -> String? {
        guard let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return key
    }

    private func fetchAPIUsage(apiKey: String) async throws -> UsageQuotaSnapshot {
        var request = URLRequest(
            url: URL(string: "https://opencode.ai/zen/go/v1/usage")!,
            timeoutInterval: 10
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GitMenuBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenCodeGoAPIError.unavailable
        }
        switch http.statusCode {
        case 200 ... 299:
            guard let snapshot = OpenCodeGoUsageParsing.snapshot(fromAPIData: data, now: now()) else {
                throw OpenCodeGoAPIError.unavailable
            }
            return snapshot
        case 401, 403:
            throw OpenCodeGoAPIError.invalidCredentials
        default:
            throw OpenCodeGoAPIError.unavailable
        }
    }
}

private enum OpenCodeGoAPIError: Error {
    case invalidCredentials
    case unavailable
}
