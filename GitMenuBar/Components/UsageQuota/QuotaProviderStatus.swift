import Foundation

/// Strip status for one quota provider, derived from the store snapshot and
/// the provider toggle. Pure mapping so the pill text stays testable.
enum QuotaProviderStatus: Equatable {
    case hidden
    case checking
    case inStrip
    case noData
    case needsKey
    case unavailable

    static func resolve(
        isEnabled: Bool,
        snapshot: UsageQuotaSnapshot?,
        isKeyProvider: Bool,
        hasStoredKey: Bool,
        selectedMetrics: [UsageQuotaPresentationPreferences.Metric]
    ) -> QuotaProviderStatus {
        guard isEnabled else { return .hidden }
        guard let snapshot else {
            return (isKeyProvider && !hasStoredKey) ? .needsKey : .checking
        }
        if snapshot.isAvailable {
            let isEligible = UsageQuotaMenuPresentation.isEligible(
                snapshot: snapshot,
                selectedMetrics: selectedMetrics
            )
            return isEligible ? .inStrip : .noData
        }
        if isKeyProvider, !hasStoredKey {
            return .needsKey
        }
        return .unavailable
    }
}
