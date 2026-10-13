import Foundation

/// Ported pricing tables for `UsageQuotaAPIPricing` (see that file for provenance).
extension UsageQuotaAPIPricing {
    static let codex: [String: CodexAPIPrice] = [
        "gpt-5": CodexAPIPrice(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil
        ),
        "gpt-5-codex": CodexAPIPrice(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil
        ),
        "gpt-5-mini": CodexAPIPrice(
            inputCostPerToken: 2.5e-7,
            outputCostPerToken: 2e-6,
            cacheReadInputCostPerToken: 2.5e-8,
            displayLabel: nil
        ),
        "gpt-5-nano": CodexAPIPrice(
            inputCostPerToken: 5e-8,
            outputCostPerToken: 4e-7,
            cacheReadInputCostPerToken: 5e-9,
            displayLabel: nil
        ),
        "gpt-5-pro": CodexAPIPrice(
            inputCostPerToken: 1.5e-5,
            outputCostPerToken: 1.2e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil
        ),
        "gpt-5.1": CodexAPIPrice(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil
        ),
        "gpt-5.1-codex": CodexAPIPrice(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil
        ),
        "gpt-5.1-codex-max": CodexAPIPrice(
            inputCostPerToken: 1.25e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1.25e-7,
            displayLabel: nil
        ),
        "gpt-5.1-codex-mini": CodexAPIPrice(
            inputCostPerToken: 2.5e-7,
            outputCostPerToken: 2e-6,
            cacheReadInputCostPerToken: 2.5e-8,
            displayLabel: nil
        ),
        "gpt-5.2": CodexAPIPrice(
            inputCostPerToken: 1.75e-6,
            outputCostPerToken: 1.4e-5,
            cacheReadInputCostPerToken: 1.75e-7,
            displayLabel: nil
        ),
        "gpt-5.2-codex": CodexAPIPrice(
            inputCostPerToken: 1.75e-6,
            outputCostPerToken: 1.4e-5,
            cacheReadInputCostPerToken: 1.75e-7,
            displayLabel: nil
        ),
        "gpt-5.2-pro": CodexAPIPrice(
            inputCostPerToken: 2.1e-5,
            outputCostPerToken: 1.68e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil
        ),
        "gpt-5.3-codex": CodexAPIPrice(
            inputCostPerToken: 1.75e-6,
            outputCostPerToken: 1.4e-5,
            cacheReadInputCostPerToken: 1.75e-7,
            displayLabel: nil
        ),
        "gpt-5.3-codex-spark": CodexAPIPrice(
            inputCostPerToken: 0,
            outputCostPerToken: 0,
            cacheReadInputCostPerToken: 0,
            displayLabel: "Research Preview"
        ),
        "gpt-5.4": CodexAPIPrice(
            inputCostPerToken: 2.5e-6,
            outputCostPerToken: 1.5e-5,
            cacheReadInputCostPerToken: 2.5e-7,
            displayLabel: nil,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 5e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheReadInputCostPerTokenAboveThreshold: 5e-7
        ),
        "gpt-5.4-mini": CodexAPIPrice(
            inputCostPerToken: 7.5e-7,
            outputCostPerToken: 4.5e-6,
            cacheReadInputCostPerToken: 7.5e-8,
            displayLabel: nil
        ),
        "gpt-5.4-nano": CodexAPIPrice(
            inputCostPerToken: 2e-7,
            outputCostPerToken: 1.25e-6,
            cacheReadInputCostPerToken: 2e-8,
            displayLabel: nil
        ),
        "gpt-5.4-pro": CodexAPIPrice(
            inputCostPerToken: 3e-5,
            outputCostPerToken: 1.8e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil
        ),
        "gpt-5.5": CodexAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 3e-5,
            cacheReadInputCostPerToken: 5e-7,
            displayLabel: nil,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 1e-5,
            outputCostPerTokenAboveThreshold: 4.5e-5,
            cacheReadInputCostPerTokenAboveThreshold: 1e-6
        ),
        "gpt-5.5-pro": CodexAPIPrice(
            inputCostPerToken: 3e-5,
            outputCostPerToken: 1.8e-4,
            cacheReadInputCostPerToken: nil,
            displayLabel: nil
        ),
        // https://developers.openai.com/api/docs/models/gpt-6-astra and /api/docs/pricing.
        // The full request switches to long-context rates above 272K input tokens, including Fast mode.
        "gpt-6-astra": CodexAPIPrice(
            inputCostPerToken: 1e-5,
            outputCostPerToken: 5e-5,
            cacheReadInputCostPerToken: 1e-6,
            displayLabel: nil,
            cacheWriteInputCostPerToken: 1.25e-5,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 2e-5,
            outputCostPerTokenAboveThreshold: 7.5e-5,
            cacheReadInputCostPerTokenAboveThreshold: 2e-6,
            cacheWriteAboveThreshold: 2.5e-5
        ),
        // GPT-5.6 Sol/Terra/Luna (OpenAI pricing page + model cards).
        // Long context: prompts with >272K input tokens are 2x input / 1.5x output for the full
        // request. Cache writes: 1.25x uncached input. API Fast support and multipliers are applied
        // separately after Standard pricing resolves from models.dev or this bundled fallback.
        "gpt-5.6-sol": CodexAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 3e-5,
            cacheReadInputCostPerToken: 5e-7,
            displayLabel: nil,
            cacheWriteInputCostPerToken: 6.25e-6,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 1e-5,
            outputCostPerTokenAboveThreshold: 4.5e-5,
            cacheReadInputCostPerTokenAboveThreshold: 1e-6,
            cacheWriteAboveThreshold: 1.25e-5
        ),
        "gpt-5.6-terra": CodexAPIPrice(
            inputCostPerToken: 2e-6,
            outputCostPerToken: 1.2e-5,
            cacheReadInputCostPerToken: 2e-7,
            displayLabel: nil,
            cacheWriteInputCostPerToken: 2.5e-6,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 4e-6,
            outputCostPerTokenAboveThreshold: 1.8e-5,
            cacheReadInputCostPerTokenAboveThreshold: 4e-7,
            cacheWriteAboveThreshold: 5e-6
        ),
        "gpt-5.6-luna": CodexAPIPrice(
            inputCostPerToken: 2e-7,
            outputCostPerToken: 1.2e-6,
            cacheReadInputCostPerToken: 2e-8,
            displayLabel: nil,
            cacheWriteInputCostPerToken: 2.5e-7,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 4e-7,
            outputCostPerTokenAboveThreshold: 1.8e-6,
            cacheReadInputCostPerTokenAboveThreshold: 4e-8,
            cacheWriteAboveThreshold: 5e-7
        ),
        // GPT-6.1 Sol (models.dev catalog snapshot 2026-10-13). Long context:
        // >272K input tokens bill 2x input / 1.5x output for the full request.
        "gpt-6.1-sol": CodexAPIPrice(
            inputCostPerToken: 2e-6,
            outputCostPerToken: 1e-5,
            cacheReadInputCostPerToken: 1e-7,
            displayLabel: nil,
            cacheWriteInputCostPerToken: 2.5e-6,
            thresholdTokens: 272_000,
            inputCostPerTokenAboveThreshold: 4e-6,
            outputCostPerTokenAboveThreshold: 1.5e-5,
            cacheReadInputCostPerTokenAboveThreshold: 2e-7,
            cacheWriteAboveThreshold: 5e-6
        )
    ]

    static let claude: [String: ClaudeAPIPrice] = [
        "claude-fable-5": ClaudeAPIPrice(
            inputCostPerToken: 1e-5,
            outputCostPerToken: 5e-5,
            cacheCreationInputCostPerToken: 1.25e-5,
            cacheReadInputCostPerToken: 1e-6,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-haiku-4-5-20251001": ClaudeAPIPrice(
            inputCostPerToken: 1e-6,
            outputCostPerToken: 5e-6,
            cacheCreationInputCostPerToken: 1.25e-6,
            cacheReadInputCostPerToken: 1e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-haiku-4-5": ClaudeAPIPrice(
            inputCostPerToken: 1e-6,
            outputCostPerToken: 5e-6,
            cacheCreationInputCostPerToken: 1.25e-6,
            cacheReadInputCostPerToken: 1e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-4-5-20251101": ClaudeAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-4-5": ClaudeAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-4-6-20260205": ClaudeAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-4-6": ClaudeAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-4-7": ClaudeAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-4-8": ClaudeAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-sonnet-4-5": ClaudeAPIPrice(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputCostPerTokenAboveThreshold: 6e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheCreationAboveThreshold: 7.5e-6,
            cacheReadInputCostPerTokenAboveThreshold: 6e-7
        ),
        "claude-sonnet-4-6": ClaudeAPIPrice(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-sonnet-4-5-20250929": ClaudeAPIPrice(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputCostPerTokenAboveThreshold: 6e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheCreationAboveThreshold: 7.5e-6,
            cacheReadInputCostPerTokenAboveThreshold: 6e-7
        ),
        "claude-opus-4-20250514": ClaudeAPIPrice(
            inputCostPerToken: 1.5e-5,
            outputCostPerToken: 7.5e-5,
            cacheCreationInputCostPerToken: 1.875e-5,
            cacheReadInputCostPerToken: 1.5e-6,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-4-1": ClaudeAPIPrice(
            inputCostPerToken: 1.5e-5,
            outputCostPerToken: 7.5e-5,
            cacheCreationInputCostPerToken: 1.875e-5,
            cacheReadInputCostPerToken: 1.5e-6,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-sonnet-4-20250514": ClaudeAPIPrice(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheCreationInputCostPerToken: 3.75e-6,
            cacheReadInputCostPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputCostPerTokenAboveThreshold: 6e-6,
            outputCostPerTokenAboveThreshold: 2.25e-5,
            cacheCreationAboveThreshold: 7.5e-6,
            cacheReadInputCostPerTokenAboveThreshold: 6e-7
        ),

        "claude-haiku-5-5": ClaudeAPIPrice(
            inputCostPerToken: 1e-7,
            outputCostPerToken: 5e-7,
            cacheCreationInputCostPerToken: 1.25e-7,
            cacheReadInputCostPerToken: 1e-8,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-sonnet-5": ClaudeAPIPrice(
            inputCostPerToken: 2e-6,
            outputCostPerToken: 1e-5,
            cacheCreationInputCostPerToken: 2.5e-6,
            cacheReadInputCostPerToken: 2e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-sonnet-5-5": ClaudeAPIPrice(
            inputCostPerToken: 2e-6,
            outputCostPerToken: 1e-5,
            cacheCreationInputCostPerToken: 2.5e-6,
            cacheReadInputCostPerToken: 1e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-5": ClaudeAPIPrice(
            inputCostPerToken: 5e-6,
            outputCostPerToken: 2.5e-5,
            cacheCreationInputCostPerToken: 6.25e-6,
            cacheReadInputCostPerToken: 5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-opus-5-5": ClaudeAPIPrice(
            inputCostPerToken: 4e-6,
            outputCostPerToken: 2e-5,
            cacheCreationInputCostPerToken: 5e-6,
            cacheReadInputCostPerToken: 2e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        ),
        "claude-fable-5-1": ClaudeAPIPrice(
            inputCostPerToken: 1e-5,
            outputCostPerToken: 5e-5,
            cacheCreationInputCostPerToken: 1.25e-5,
            cacheReadInputCostPerToken: 2.5e-7,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheCreationAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil
        )
    ]
}
