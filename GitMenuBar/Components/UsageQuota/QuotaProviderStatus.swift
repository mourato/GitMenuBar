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
        hasStoredKey: Bool
    ) -> QuotaProviderStatus {
        guard isEnabled else { return .hidden }
        guard let snapshot else { return .checking }
        if snapshot.isAvailable {
            let isEligible = snapshot.primaryDisplayWindow != nil
                || snapshot.tertiaryMonthlyWindow != nil
                || !snapshot.modelWindows.isEmpty
            return isEligible ? .inStrip : .noData
        }
        if isKeyProvider, !hasStoredKey {
            return .needsKey
        }
        return .unavailable
    }
}
