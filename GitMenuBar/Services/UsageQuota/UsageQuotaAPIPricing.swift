import Foundation

/// API-equivalent per-token pricing used by the monthly spend-estimate card.
///
/// Built-in tables are ported from CodexBar's `CostUsagePricing` (MIT,
/// Peter Steinberger — see THIRD-PARTY-NOTICES.md); the `claude-*-5` rows
/// come from a models.dev catalog snapshot (2026-10-07) and need re-checking
/// when the table is next updated. Token math mirrors CodexBar: Codex
/// `input_tokens` already includes cached reads as a subset, so cached and
/// written tokens are split out before billing; Claude bills 1h cache
/// creation at 2x the input rate.
///
/// Resolution is catalog-first (live models.dev data, ported from CodexBar's
/// `ModelsDevPricing.swift`); the bundled tables below are the offline
/// fallback, so new model IDs price correctly once the catalog is cached.
enum UsageQuotaAPIPricing {
    struct CodexAPIPrice {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheReadInputCostPerToken: Double?
        let cacheWriteInputCostPerToken: Double?
        let thresholdTokens: Int?
        let inputCostPerTokenAboveThreshold: Double?
        let outputCostPerTokenAboveThreshold: Double?
        let cacheReadInputCostPerTokenAboveThreshold: Double?
        let cacheWriteAboveThreshold: Double?

        init(
            inputCostPerToken: Double,
            outputCostPerToken: Double,
            cacheReadInputCostPerToken: Double?,
            displayLabel _: String?,
            cacheWriteInputCostPerToken: Double? = nil,
            thresholdTokens: Int? = nil,
            inputCostPerTokenAboveThreshold: Double? = nil,
            outputCostPerTokenAboveThreshold: Double? = nil,
            cacheReadInputCostPerTokenAboveThreshold: Double? = nil,
            cacheWriteAboveThreshold: Double? = nil
        ) {
            self.inputCostPerToken = inputCostPerToken
            self.outputCostPerToken = outputCostPerToken
            self.cacheReadInputCostPerToken = cacheReadInputCostPerToken
            self.cacheWriteInputCostPerToken = cacheWriteInputCostPerToken
            self.thresholdTokens = thresholdTokens
            self.inputCostPerTokenAboveThreshold = inputCostPerTokenAboveThreshold
            self.outputCostPerTokenAboveThreshold = outputCostPerTokenAboveThreshold
            self.cacheReadInputCostPerTokenAboveThreshold = cacheReadInputCostPerTokenAboveThreshold
            self.cacheWriteAboveThreshold = cacheWriteAboveThreshold
        }
    }

    struct ClaudeAPIPrice {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheCreationInputCostPerToken: Double
        let cacheReadInputCostPerToken: Double
        let thresholdTokens: Int?
        let inputCostPerTokenAboveThreshold: Double?
        let outputCostPerTokenAboveThreshold: Double?
        let cacheCreationAboveThreshold: Double?
        let cacheReadInputCostPerTokenAboveThreshold: Double?
    }

    static func normalizeCodexModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }
        if trimmed == "gpt-5.6" {
            return "gpt-5.6-sol"
        }
        if trimmed == "gpt-reserve" {
            return "gpt-5.6-luna"
        }
        if codex[trimmed] != nil {
            return trimmed
        }
        if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<datedSuffix.lowerBound])
            if codex[base] != nil {
                return base
            }
        }
        return trimmed
    }

    static func normalizeClaudeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("anthropic.") {
            trimmed = String(trimmed.dropFirst("anthropic.".count))
        }
        if let baseRange = trimmed.range(of: #"-\d{8}$"#, options: .regularExpression) {
            let base = String(trimmed[..<baseRange.lowerBound])
            if claude[base] != nil {
                return base
            }
        }
        return trimmed
    }

    // MARK: - Catalog resolution

    /// models.dev publishes USD per 1M tokens; token math uses USD per token.
    private static let catalogUnit = 1_000_000.0
    /// A models.dev `context_over_200k` block implies a 200K-token switch.
    private static let catalogContextThresholdTokens = 200_000

    /// Catalog-first resolution; the bundled table is the offline fallback.
    static func codexPricing(
        for model: String,
        catalog: ModelsDevCatalog?
    ) -> CodexAPIPrice? {
        let entry = catalog?.model(providerID: "openai", rawModelID: model)
            ?? catalog?.model(providerID: "openai", rawModelID: normalizeCodexModel(model))
        if let cost = entry?.cost,
           let input = cost.input,
           let output = cost.output
        {
            let context = cost.contextOver200K
            return CodexAPIPrice(
                inputCostPerToken: input / catalogUnit,
                outputCostPerToken: output / catalogUnit,
                cacheReadInputCostPerToken: cost.cacheRead.map { $0 / catalogUnit },
                displayLabel: nil,
                cacheWriteInputCostPerToken: cost.cacheWrite.map { $0 / catalogUnit },
                thresholdTokens: context.map { _ in catalogContextThresholdTokens },
                inputCostPerTokenAboveThreshold: context?.input.map { $0 / catalogUnit },
                outputCostPerTokenAboveThreshold: context?.output.map { $0 / catalogUnit },
                cacheReadInputCostPerTokenAboveThreshold: context?.cacheRead.map { $0 / catalogUnit },
                cacheWriteAboveThreshold: context?.cacheWrite.map { $0 / catalogUnit }
            )
        }
        return codex[normalizeCodexModel(model)]
    }

    /// Catalog-first resolution; the bundled table is the offline fallback.
    /// Missing cache rates fall back to the input rate, matching Claude's
    /// documented cache pricing and CodexBar's models.dev conversion.
    static func claudePricing(
        for model: String,
        catalog: ModelsDevCatalog?
    ) -> ClaudeAPIPrice? {
        if let cost = catalog?.model(providerID: "anthropic", rawModelID: model)?.cost,
           let input = cost.input,
           let output = cost.output
        {
            let context = cost.contextOver200K
            return ClaudeAPIPrice(
                inputCostPerToken: input / catalogUnit,
                outputCostPerToken: output / catalogUnit,
                cacheCreationInputCostPerToken: (cost.cacheWrite ?? input) / catalogUnit,
                cacheReadInputCostPerToken: (cost.cacheRead ?? input) / catalogUnit,
                thresholdTokens: context.map { _ in catalogContextThresholdTokens },
                inputCostPerTokenAboveThreshold: context?.input.map { $0 / catalogUnit },
                outputCostPerTokenAboveThreshold: context?.output.map { $0 / catalogUnit },
                cacheCreationAboveThreshold: context?.cacheWrite.map { $0 / catalogUnit },
                cacheReadInputCostPerTokenAboveThreshold: context?.cacheRead.map { $0 / catalogUnit }
            )
        }
        return claude[normalizeClaudeModel(model)]
    }

    static func codexCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int,
        catalog: ModelsDevCatalog? = nil
    ) -> Double? {
        guard let pricing = codexPricing(for: model, catalog: catalog) else { return nil }
        let totalInput = max(0, inputTokens)
        let cached = min(max(0, cachedInputTokens), totalInput)
        let remainingAfterCache = totalInput - cached
        let cacheWrite = min(max(0, cacheWriteInputTokens), remainingAfterCache)
        let nonCached = remainingAfterCache - cacheWrite
        let cachedRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken
        let usesLongContextRates = pricing.thresholdTokens.map { totalInput > $0 } ?? false
        let inputRate = usesLongContextRates
            ? pricing.inputCostPerTokenAboveThreshold ?? pricing.inputCostPerToken
            : pricing.inputCostPerToken
        let cachedInputRate = usesLongContextRates
            ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken ?? inputRate
            : cachedRate
        let cacheWriteRate = usesLongContextRates
            ? pricing.cacheWriteAboveThreshold
            ?? pricing.cacheWriteInputCostPerToken
            ?? inputRate
            : pricing.cacheWriteInputCostPerToken ?? inputRate
        let outputRate = usesLongContextRates
            ? pricing.outputCostPerTokenAboveThreshold ?? pricing.outputCostPerToken
            : pricing.outputCostPerToken
        return Double(nonCached) * inputRate
            + Double(cached) * cachedInputRate
            + Double(cacheWrite) * cacheWriteRate
            + Double(max(0, outputTokens)) * outputRate
    }

    static func claudeCostUSD(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheCreationInputTokens1h: Int = 0,
        outputTokens: Int,
        catalog: ModelsDevCatalog? = nil
    ) -> Double? {
        guard let pricing = claudePricing(for: model, catalog: catalog) else { return nil }
        let input = max(0, inputTokens)
        let cacheRead = max(0, cacheReadInputTokens)
        let cacheCreationTotal = max(0, cacheCreationInputTokens)
        let cacheCreation1h = min(max(0, cacheCreationInputTokens1h), cacheCreationTotal)
        let cacheCreation5m = cacheCreationTotal - cacheCreation1h
        let usesLongContextRates = pricing.thresholdTokens.map { input + cacheRead + cacheCreationTotal > $0 } ?? false
        let inputRate = usesLongContextRates
            ? pricing.inputCostPerTokenAboveThreshold ?? pricing.inputCostPerToken
            : pricing.inputCostPerToken
        let cacheReadRate = usesLongContextRates
            ? pricing.cacheReadInputCostPerTokenAboveThreshold ?? pricing.cacheReadInputCostPerToken
            : pricing.cacheReadInputCostPerToken
        let cacheCreation5mRate = usesLongContextRates
            ? pricing.cacheCreationAboveThreshold ?? pricing.cacheCreationInputCostPerToken
            : pricing.cacheCreationInputCostPerToken
        let outputRate = usesLongContextRates
            ? pricing.outputCostPerTokenAboveThreshold ?? pricing.outputCostPerToken
            : pricing.outputCostPerToken
        return Double(input) * inputRate
            + Double(cacheRead) * cacheReadRate
            + Double(cacheCreation5m) * cacheCreation5mRate
            + Double(cacheCreation1h) * inputRate * 2
            + Double(max(0, outputTokens)) * outputRate
    }
}
