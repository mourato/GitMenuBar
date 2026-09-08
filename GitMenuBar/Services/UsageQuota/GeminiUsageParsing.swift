import Foundation

enum GeminiUsageParsing {
    struct ModelQuota: Equatable, Sendable {
        let modelId: String
        let percentLeft: Int
        let resetAt: Date?
    }

    private struct QuotaResponse: Decodable {
        let buckets: [QuotaBucket]?
    }

    private struct QuotaBucket: Decodable {
        let modelId: String?
        let remainingFraction: Double?
        let resetTime: String?
    }

    static func parseAPIResponse(_ data: Data) throws -> [ModelQuota] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(QuotaResponse.self, from: data)

        guard let buckets = response.buckets, !buckets.isEmpty else {
            return []
        }

        var modelQuotaMap: [String: (fraction: Double, resetString: String?)] = [:]

        for bucket in buckets {
            guard let modelId = bucket.modelId, let fraction = bucket.remainingFraction else { continue }
            if let existing = modelQuotaMap[modelId] {
                if fraction < existing.fraction {
                    modelQuotaMap[modelId] = (fraction, bucket.resetTime)
                }
            } else {
                modelQuotaMap[modelId] = (fraction, bucket.resetTime)
            }
        }

        return modelQuotaMap
            .sorted { $0.key < $1.key }
            .map { modelId, info in
                let resetDate = info.resetString.flatMap { parseResetTime($0) }
                let percentLeft = max(0, min(100, Int((info.fraction * 100).rounded())))
                return ModelQuota(
                    modelId: modelId,
                    percentLeft: percentLeft,
                    resetAt: resetDate
                )
            }
    }

    static func parseResetTime(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }

    static func isFlashLiteModel(id: String) -> Bool {
        id.lowercased().contains("flash-lite")
    }

    static func isFlashModel(id: String) -> Bool {
        let lower = id.lowercased()
        return lower.contains("flash") && !isFlashLiteModel(id: lower)
    }

    static func isProModel(id: String) -> Bool {
        id.lowercased().contains("pro")
    }

    static func snapshot(
        from quotas: [ModelQuota],
        now: Date = Date()
    ) -> UsageQuotaSnapshot {
        guard !quotas.isEmpty else {
            return .unavailable(providerID: .gemini, statusNote: "no quota reported")
        }

        let proQuotas = quotas.filter { isProModel(id: $0.modelId) }
        let flashQuotas = quotas.filter { isFlashModel(id: $0.modelId) }

        let proMin = proQuotas.min(by: { $0.percentLeft < $1.percentLeft })
        let flashMin = flashQuotas.min(by: { $0.percentLeft < $1.percentLeft })

        let sessionWindow: UsageWindow? = if let proMin {
            UsageWindow(
                remainingPercent: proMin.percentLeft,
                resetAt: proMin.resetAt,
                label: "Pro",
                durationSeconds: 86400
            )
        } else if let first = quotas.first {
            UsageWindow(
                remainingPercent: first.percentLeft,
                resetAt: first.resetAt,
                label: "Gemini",
                durationSeconds: 86400
            )
        } else {
            nil
        }

        let weeklyWindow: UsageWindow? = if let flashMin, proMin != nil {
            UsageWindow(
                remainingPercent: flashMin.percentLeft,
                resetAt: flashMin.resetAt,
                label: "Flash",
                durationSeconds: 86400
            )
        } else if proMin == nil, let flashMin {
            UsageWindow(
                remainingPercent: flashMin.percentLeft,
                resetAt: flashMin.resetAt,
                label: "Flash",
                durationSeconds: 86400
            )
        } else {
            nil
        }

        return UsageQuotaSnapshot(
            providerID: .gemini,
            displayName: UsageProviderID.gemini.displayName,
            sessionWindow: sessionWindow,
            weeklyWindow: weeklyWindow,
            creditValueText: nil,
            isAvailable: true,
            fetchedAt: now
        )
    }
}
