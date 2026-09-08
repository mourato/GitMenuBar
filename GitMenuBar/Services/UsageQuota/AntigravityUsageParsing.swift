import Foundation

private struct AntigravityQuotaSummaryRemaining: Decodable {
    let remainingFraction: Double?

    private enum CodingKeys: String, CodingKey {
        case remainingFraction
        case oneofCase = "case"
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let remainingFraction = try container.decodeIfPresent(Double.self, forKey: .remainingFraction) {
            self.remainingFraction = remainingFraction
        } else if try container.decodeIfPresent(String.self, forKey: .oneofCase) == "remainingFraction" {
            remainingFraction = try container.decodeIfPresent(Double.self, forKey: .value)
        } else {
            remainingFraction = nil
        }
    }
}

enum AntigravityUsageParsing {
    struct ModelQuota: Equatable, Sendable {
        let label: String
        let modelId: String
        let remainingFraction: Double
        let resetAt: Date?
        let isDisabled: Bool

        init(
            label: String,
            modelId: String,
            remainingFraction: Double,
            resetAt: Date?,
            isDisabled: Bool = false
        ) {
            self.label = label
            self.modelId = modelId
            self.remainingFraction = remainingFraction
            self.resetAt = resetAt
            self.isDisabled = isDisabled
        }

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

    private struct CommandModelConfigResponse: Decodable {
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
        let response: QuotaSummaryPayload?
        let summary: QuotaSummaryPayload?
        let groups: [QuotaGroup]?

        var resolvedGroups: [QuotaGroup]? {
            response?.groups ?? summary?.groups ?? groups
        }
    }

    private struct QuotaSummaryPayload: Decodable {
        let groups: [QuotaGroup]?
    }

    private struct QuotaGroup: Decodable {
        let displayName: String?
        let name: String?
        let buckets: [QuotaBucket]?

        var resolvedName: String {
            displayName?.nonEmptyTrimmed ?? name?.nonEmptyTrimmed ?? "Quota"
        }
    }

    private struct QuotaBucket: Decodable {
        let bucketId: String?
        let displayName: String?
        let description: String?
        let disabled: Bool?
        let modelId: String?
        let remainingFraction: Double?
        let remaining: AntigravityQuotaSummaryRemaining?
        let resetTime: String?

        var resolvedModelId: String? {
            bucketId?.nonEmptyTrimmed
                ?? modelId?.nonEmptyTrimmed
                ?? displayName?.nonEmptyTrimmed
        }

        var resolvedRemainingFraction: Double? {
            remainingFraction ?? remaining?.remainingFraction
        }
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

    static func parseCommandModelConfigResponse(_ data: Data) throws -> [ModelQuota] {
        let response = try JSONDecoder().decode(CommandModelConfigResponse.self, from: data)
        return response.clientModelConfigs?.compactMap { config in
            guard let quota = config.quotaInfo,
                  let fraction = quota.remainingFraction
            else { return nil }
            let label = config.label ?? ""
            return ModelQuota(
                label: label,
                modelId: config.modelOrAlias?.model ?? label,
                remainingFraction: fraction,
                resetAt: quota.resetTime.flatMap(parseDate)
            )
        } ?? []
    }

    static func parseQuotaSummaryResponse(_ data: Data) throws -> [ModelQuota] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(QuotaSummaryResponse.self, from: data)

        guard let groups = response.resolvedGroups else { return [] }

        var results: [ModelQuota] = []
        for group in groups {
            let groupName = group.resolvedName
            for bucket in group.buckets ?? [] {
                guard let fraction = bucket.resolvedRemainingFraction,
                      let modelId = bucket.resolvedModelId
                else { continue }
                let resetDate = bucket.resetTime.flatMap { parseDate($0) }
                results.append(ModelQuota(
                    label: bucket.displayName?.nonEmptyTrimmed ?? groupName,
                    modelId: modelId,
                    remainingFraction: fraction,
                    resetAt: resetDate,
                    isDisabled: bucket.disabled ?? false
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
            guard let fraction = bucket.resolvedRemainingFraction,
                  let modelId = bucket.resolvedModelId
            else { return nil }
            let resetDate = bucket.resetTime.flatMap { parseDate($0) }
            return ModelQuota(
                label: bucket.displayName?.nonEmptyTrimmed ?? modelId,
                modelId: modelId,
                remainingFraction: fraction,
                resetAt: resetDate,
                isDisabled: bucket.disabled ?? false
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

    static func isSessionQuota(modelId: String, label: String) -> Bool {
        let combined = "\(modelId) \(label)".lowercased()
        return combined.contains("5h")
            || combined.contains("5-hour")
            || combined.contains("five hour")
            || combined.contains("session")
    }

    static func isWeeklyQuota(modelId: String, label: String) -> Bool {
        let combined = "\(modelId) \(label)".lowercased()
        return combined.contains("weekly") || combined.contains("7d") || combined.contains("7-day")
    }

    static func snapshot(
        from quotas: [ModelQuota],
        now: Date = Date()
    ) -> UsageQuotaSnapshot {
        guard !quotas.isEmpty else {
            return .unavailable(providerID: .antigravity, statusNote: "no quota reported")
        }

        let usableQuotas = quotas.filter { !$0.isDisabled }
        let sessionQuotas = usableQuotas.filter { isSessionQuota(modelId: $0.modelId, label: $0.label) }
        let weeklyQuotas = usableQuotas.filter { isWeeklyQuota(modelId: $0.modelId, label: $0.label) }

        let geminiQuotas = usableQuotas.filter { isGeminiModel(modelId: $0.modelId, label: $0.label) }
        let claudeGptQuotas = usableQuotas.filter { isClaudeOrGPTModel(modelId: $0.modelId, label: $0.label) }

        let sessionMin = sessionQuotas.min(by: { $0.remainingFraction < $1.remainingFraction })
        let weeklyMin = weeklyQuotas.min(by: { $0.remainingFraction < $1.remainingFraction })
        let geminiMin = geminiQuotas.min(by: { $0.remainingFraction < $1.remainingFraction })
        let claudeGptMin = claudeGptQuotas.min(by: { $0.remainingFraction < $1.remainingFraction })

        let hasExplicitWindows = !sessionQuotas.isEmpty || !weeklyQuotas.isEmpty

        let sessionWindow: UsageWindow? = if hasExplicitWindows, let sessionMin {
            UsageWindow(
                remainingPercent: sessionMin.percentLeft,
                resetAt: sessionMin.resetAt,
                label: sessionMin.label.isEmpty ? "Session" : sessionMin.label,
                durationSeconds: 18000
            )
        } else if let geminiMin {
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

        let weeklyWindow: UsageWindow? = if hasExplicitWindows, let weeklyMin {
            UsageWindow(
                remainingPercent: weeklyMin.percentLeft,
                resetAt: weeklyMin.resetAt,
                label: weeklyMin.label.isEmpty ? "Weekly" : weeklyMin.label,
                durationSeconds: 604_800
            )
        } else if let claudeGptMin {
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

private extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
