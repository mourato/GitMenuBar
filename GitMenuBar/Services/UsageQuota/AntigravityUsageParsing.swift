import Foundation

enum AntigravityUsageParsing {
    struct ModelQuota: Equatable, Sendable {
        let label: String
        let modelId: String
        let remainingFraction: Double
        let resetAt: Date?

        var percentLeft: Int {
            max(0, min(100, Int((remainingFraction * 100).rounded())))
        }
    }

    // MARK: - GetUserStatus JSON Structures

    private struct UserStatusResponse: Decodable {
        let userStatus: UserStatus?
    }

    private struct UserStatus: Decodable {
        let email: String?
        let cascadeModelConfigData: CascadeModelConfigData?
    }

    private struct CascadeModelConfigData: Decodable {
        let clientModelConfigs: [ClientModelConfig]?
    }

    private struct ClientModelConfig: Decodable {
        let label: String?
        let modelOrAlias: ModelOrAlias?
        let quotaInfo: QuotaInfo?
    }

    private struct ModelOrAlias: Decodable {
        let model: String?
    }

    private struct QuotaInfo: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
    }

    // MARK: - RetrieveUserQuotaSummary JSON Structures

    private struct QuotaSummaryResponse: Decodable {
        let groups: [QuotaGroup]?
    }

    private struct QuotaGroup: Decodable {
        let name: String?
        let buckets: [QuotaBucket]?
    }

    private struct QuotaBucket: Decodable {
        let modelId: String?
        let remainingFraction: Double?
        let resetTime: String?
    }

    // MARK: - Parsing

    static func parseUserStatusResponse(_ data: Data) throws -> [ModelQuota] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(UserStatusResponse.self, from: data)

        guard let configs = response.userStatus?.cascadeModelConfigData?.clientModelConfigs else {
            return []
        }

        return configs.compactMap { config in
            guard let quota = config.quotaInfo,
                  let fraction = quota.remainingFraction
            else {
                return nil
            }
            let label = config.label ?? ""
            let modelId = config.modelOrAlias?.model ?? label
            let resetDate = quota.resetTime.flatMap { parseDate($0) }
            return ModelQuota(
                label: label,
                modelId: modelId,
                remainingFraction: fraction,
                resetAt: resetDate
            )
        }
    }

    static func parseQuotaSummaryResponse(_ data: Data) throws -> [ModelQuota] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(QuotaSummaryResponse.self, from: data)

        guard let groups = response.groups else { return [] }

        var results: [ModelQuota] = []
        for group in groups {
            let groupName = group.name ?? "Quota"
            for bucket in group.buckets ?? [] {
                guard let fraction = bucket.remainingFraction else { continue }
                let modelId = bucket.modelId ?? groupName
                let resetDate = bucket.resetTime.flatMap { parseDate($0) }
                results.append(ModelQuota(
                    label: groupName,
                    modelId: modelId,
                    remainingFraction: fraction,
                    resetAt: resetDate
                ))
            }
        }
        return results
    }

    static func parseRemoteQuotaResponse(_ data: Data) throws -> [ModelQuota] {
        struct RemoteResponse: Decodable {
            let buckets: [QuotaBucket]?
        }
        let decoder = JSONDecoder()
        let response = try decoder.decode(RemoteResponse.self, from: data)
        guard let buckets = response.buckets else { return [] }

        return buckets.compactMap { bucket in
            guard let fraction = bucket.remainingFraction else { return nil }
            let modelId = bucket.modelId ?? "Model"
            let resetDate = bucket.resetTime.flatMap { parseDate($0) }
            return ModelQuota(
                label: modelId,
                modelId: modelId,
                remainingFraction: fraction,
                resetAt: resetDate
            )
        }
    }

    static func parseDate(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: string) {
            return date
        }
        if let seconds = Double(string) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    // MARK: - Model Classification

    static func isGeminiModel(modelId: String, label: String) -> Bool {
        let combined = "\(modelId) \(label)".lowercased()
        return combined.contains("gemini")
    }

    static func isClaudeOrGPTModel(modelId: String, label: String) -> Bool {
        let combined = "\(modelId) \(label)".lowercased()
        return combined.contains("claude") || combined.contains("gpt") || combined.contains("openai")
    }

    static func snapshot(
        from quotas: [ModelQuota],
        now: Date = Date()
    ) -> UsageQuotaSnapshot {
        guard !quotas.isEmpty else {
            return .unavailable(providerID: .antigravity, statusNote: "no quota reported")
        }

        let geminiQuotas = quotas.filter { isGeminiModel(modelId: $0.modelId, label: $0.label) }
        let claudeGptQuotas = quotas.filter { isClaudeOrGPTModel(modelId: $0.modelId, label: $0.label) }

        let geminiMin = geminiQuotas.min(by: { $0.remainingFraction < $1.remainingFraction })
        let claudeGptMin = claudeGptQuotas.min(by: { $0.remainingFraction < $1.remainingFraction })

        let sessionWindow: UsageWindow? = if let geminiMin {
            UsageWindow(
                remainingPercent: geminiMin.percentLeft,
                resetAt: geminiMin.resetAt,
                label: "Gemini",
                durationSeconds: 18000 // 5 hours
            )
        } else if let first = quotas.first, claudeGptMin == nil {
            UsageWindow(
                remainingPercent: first.percentLeft,
                resetAt: first.resetAt,
                label: first.label.isEmpty ? "Antigravity" : first.label,
                durationSeconds: 18000
            )
        } else {
            nil
        }

        let weeklyWindow: UsageWindow? = if let claudeGptMin {
            UsageWindow(
                remainingPercent: claudeGptMin.percentLeft,
                resetAt: claudeGptMin.resetAt,
                label: "Claude/GPT",
                durationSeconds: 604_800 // 7 days
            )
        } else {
            nil
        }

        guard sessionWindow != nil || weeklyWindow != nil else {
            return .unavailable(providerID: .antigravity, statusNote: "no model quotas found")
        }

        return UsageQuotaSnapshot(
            providerID: .antigravity,
            displayName: UsageProviderID.antigravity.displayName,
            sessionWindow: sessionWindow,
            weeklyWindow: weeklyWindow,
            creditValueText: nil,
            isAvailable: true,
            fetchedAt: now
        )
    }
}
