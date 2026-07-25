import Foundation

struct UsageQuotaSnapshotStore {
    private let defaults: UserDefaults
    private let keyPrefix = "usageQuotaSnapshot.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(providerID: UsageProviderID) -> UsageQuotaSnapshot? {
        guard let data = defaults.data(forKey: storageKey(for: providerID)) else { return nil }
        return try? JSONDecoder().decode(UsageQuotaSnapshot.self, from: data)
    }

    func save(_ snapshot: UsageQuotaSnapshot) {
        guard snapshot.isAvailable else { return }
        guard snapshot.sessionWindow != nil || snapshot.weeklyWindow != nil || snapshot.creditValueText != nil else {
            return
        }

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey(for: snapshot.providerID))
    }

    func remove(providerID: UsageProviderID) {
        defaults.removeObject(forKey: storageKey(for: providerID))
    }

    func removeAll() {
        for providerID in UsageProviderID.allCases {
            remove(providerID: providerID)
        }
    }

    private func storageKey(for providerID: UsageProviderID) -> String {
        keyPrefix + providerID.rawValue
    }
}
