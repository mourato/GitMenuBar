import Foundation

protocol UsageQuotaProviding: Sendable {
    var id: UsageProviderID { get }

    func fetchSnapshot() async -> UsageQuotaSnapshot
}
