import Foundation

struct OpenRouterUsageState: Codable, Equatable, Sendable {
    let totalCredits: Double
    let totalUsage: Double
    let quotaBaseCredits: Double
    let usageAtQuotaBase: Double

    func updating(totalCredits: Double, totalUsage: Double) -> OpenRouterUsageState {
        if totalCredits > self.totalCredits {
            let previousUsage = max(0, self.totalUsage - usageAtQuotaBase)
            let previousBalance = max(0, quotaBaseCredits - previousUsage)
            return OpenRouterUsageState(
                totalCredits: totalCredits,
                totalUsage: totalUsage,
                quotaBaseCredits: previousBalance + (totalCredits - self.totalCredits),
                usageAtQuotaBase: self.totalUsage
            )
        }

        if totalCredits < self.totalCredits {
            return OpenRouterUsageState(
                totalCredits: totalCredits,
                totalUsage: totalUsage,
                quotaBaseCredits: totalCredits,
                usageAtQuotaBase: 0
            )
        }

        return OpenRouterUsageState(
            totalCredits: totalCredits,
            totalUsage: totalUsage,
            quotaBaseCredits: quotaBaseCredits,
            usageAtQuotaBase: usageAtQuotaBase
        )
    }
}

struct OpenRouterUsageStateStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "openRouterUsageState.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> OpenRouterUsageState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OpenRouterUsageState.self, from: data)
    }

    func save(_ state: OpenRouterUsageState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Parsing helpers for OpenRouter's credits API.
/// Credits parsing adapted from CodexBar (MIT, steipete).
enum OpenRouterUsageParsing {
    struct ParsedCredits: Sendable {
        let snapshot: UsageQuotaSnapshot
        let state: OpenRouterUsageState
    }

    private struct CreditsResponse: Decodable {
        let data: CreditsData
    }

    private struct CreditsData: Decodable {
        let totalCredits: Double
        let totalUsage: Double
    }

    static func parse(
        fromCreditsData data: Data,
        previousState: OpenRouterUsageState? = nil
    ) -> ParsedCredits? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(CreditsResponse.self, from: data) else {
            return nil
        }

        let totalCredits = response.data.totalCredits
        let totalUsage = response.data.totalUsage
        let currentBalance = max(0, totalCredits - totalUsage)
        let state = previousState?.updating(totalCredits: totalCredits, totalUsage: totalUsage)
            ?? OpenRouterUsageState(
                totalCredits: totalCredits,
                totalUsage: totalUsage,
                quotaBaseCredits: currentBalance,
                usageAtQuotaBase: totalUsage
            )
        let usedSinceQuotaBase = max(0, totalUsage - state.usageAtQuotaBase)
        let usedPercent = state.quotaBaseCredits > 0
            ? min(100, (usedSinceQuotaBase / state.quotaBaseCredits) * 100)
            : 0
        let balance = max(0, state.quotaBaseCredits - usedSinceQuotaBase)

        return ParsedCredits(
            snapshot: UsageQuotaSnapshot(
                providerID: .openrouter,
                displayName: UsageProviderID.openrouter.displayName,
                sessionWindow: UsageWindow(
                    remainingPercent: UsageQuotaFormatting.remainingPercent(fromUsed: usedPercent),
                    resetAt: nil,
                    label: "Credits",
                    durationSeconds: nil
                ),
                weeklyWindow: nil,
                creditValueText: String(format: "$%.2f left", balance),
                isAvailable: true,
                statusNote: "openrouter credits api"
            ),
            state: state
        )
    }

    /// Parse `GET https://openrouter.ai/api/v1/credits` into a snapshot.
    /// Credits have no reset window, so `sessionWindow` carries `resetAt: nil`.
    static func snapshot(fromCreditsData data: Data) -> UsageQuotaSnapshot? {
        parse(fromCreditsData: data)?.snapshot
    }
}
