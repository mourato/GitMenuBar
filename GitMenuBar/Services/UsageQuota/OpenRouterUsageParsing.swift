import Foundation

/// Parsing helpers for OpenRouter's credits API.
/// Credits parsing adapted from CodexBar (MIT, steipete).
enum OpenRouterUsageParsing {
    private struct CreditsResponse: Decodable {
        let data: CreditsData
    }

    private struct CreditsData: Decodable {
        let totalCredits: Double
        let totalUsage: Double
    }

    /// Parse `GET https://openrouter.ai/api/v1/credits` into a snapshot.
    /// Credits have no reset window, so `sessionWindow` carries `resetAt: nil`.
    static func snapshot(fromCreditsData data: Data) -> UsageQuotaSnapshot? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(CreditsResponse.self, from: data) else {
            return nil
        }

        let totalCredits = response.data.totalCredits
        let totalUsage = response.data.totalUsage
        let usedPercent = totalCredits > 0 ? min(100, (totalUsage / totalCredits) * 100) : 0
        let balance = max(0, totalCredits - totalUsage)

        return UsageQuotaSnapshot(
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
        )
    }
}
