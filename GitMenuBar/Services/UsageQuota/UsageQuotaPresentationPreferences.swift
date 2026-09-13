import Combine
import Foundation

@MainActor
final class UsageQuotaPresentationPreferences: ObservableObject {
    enum MeterStyle: String, CaseIterable, Identifiable {
        case text
        case bars

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .text:
                "Text"
            case .bars:
                "Bars"
            }
        }
    }

    enum ValueStyle: String, CaseIterable, Identifiable {
        case left
        case used

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .left:
                "Left"
            case .used:
                "Used"
            }
        }
    }

    enum MenuBarVisibility: String, CaseIterable, Identifiable {
        case always
        case menuOnly

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .always:
                "Always"
            case .menuOnly:
                "Menu only"
            }
        }
    }

    enum Metric: String, CaseIterable, Identifiable {
        case session
        case weekly
        case credits

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .session:
                "Session"
            case .weekly:
                "Weekly"
            case .credits:
                "Credits"
            }
        }
    }

    @Published var meterStyle: MeterStyle {
        didSet { defaults.set(meterStyle.rawValue, forKey: AppPreferences.Keys.usageQuotaMenuBarStyle) }
    }

    @Published var valueStyle: ValueStyle {
        didSet { defaults.set(valueStyle.rawValue, forKey: AppPreferences.Keys.usageQuotaValueStyle) }
    }

    @Published var menuBarVisibility: MenuBarVisibility {
        didSet { defaults.set(menuBarVisibility.rawValue, forKey: AppPreferences.Keys.usageQuotaMenuBarVisibility) }
    }

    @Published private(set) var providerOrder: [UsageProviderID] {
        didSet { saveProviderOrder() }
    }

    private let defaults: UserDefaults
    private var metricsByProvider: [UsageProviderID: [Metric]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        meterStyle = defaults.string(forKey: AppPreferences.Keys.usageQuotaMenuBarStyle)
            .flatMap(MeterStyle.init(rawValue:)) ?? .text
        valueStyle = defaults.string(forKey: AppPreferences.Keys.usageQuotaValueStyle)
            .flatMap(ValueStyle.init(rawValue:)) ?? .left
        menuBarVisibility = defaults.string(forKey: AppPreferences.Keys.usageQuotaMenuBarVisibility)
            .flatMap(MenuBarVisibility.init(rawValue:)) ?? .always

        let storedOrder = (defaults.array(forKey: AppPreferences.Keys.usageQuotaProviderOrder) as? [String] ?? [])
            .compactMap(UsageProviderID.init(rawValue:))
        providerOrder = storedOrder
        metricsByProvider = Self.loadMetrics(defaults: defaults)
    }

    var orderedProviderIDs: [UsageProviderID] {
        let configured = providerOrder.filter { UsageProviderID.allCases.contains($0) }
        return configured + UsageProviderID.allCases.filter { !configured.contains($0) }
    }

    func selectedMetrics(for providerID: UsageProviderID) -> [Metric] {
        metricsByProvider[providerID] ?? [.session, .weekly]
    }

    func setSelectedMetrics(_ metrics: [Metric], for providerID: UsageProviderID) {
        var unique: [Metric] = []
        for metric in metrics where !unique.contains(metric) {
            unique.append(metric)
            if unique.count == 2 {
                break
            }
        }
        guard unique != selectedMetrics(for: providerID) else { return }
        objectWillChange.send()
        metricsByProvider[providerID] = unique
        saveMetrics()
    }

    func toggleMetric(_ metric: Metric, for providerID: UsageProviderID) {
        var selected = selectedMetrics(for: providerID)
        if let index = selected.firstIndex(of: metric) {
            selected.remove(at: index)
        } else if selected.count < 2 {
            selected.append(metric)
        } else {
            selected[1] = metric
        }
        setSelectedMetrics(selected, for: providerID)
    }

    func moveProvider(from offsets: IndexSet, to destination: Int) {
        var order = orderedProviderIDs
        order.move(fromOffsets: offsets, toOffset: destination)
        guard order != orderedProviderIDs else { return }
        providerOrder = order
    }

    func moveProvider(_ providerID: UsageProviderID, by offset: Int) {
        var order = orderedProviderIDs
        guard let index = order.firstIndex(of: providerID) else { return }
        let destination = index + offset
        guard order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        providerOrder = order
    }

    private func saveProviderOrder() {
        defaults.set(providerOrder.map(\.rawValue), forKey: AppPreferences.Keys.usageQuotaProviderOrder)
    }

    private func saveMetrics() {
        let values = metricsByProvider.reduce(into: [String: [String]]()) { result, entry in
            result[entry.key.rawValue] = entry.value.map(\.rawValue)
        }
        defaults.set(values, forKey: AppPreferences.Keys.usageQuotaMetrics)
    }

    private static func loadMetrics(defaults: UserDefaults) -> [UsageProviderID: [Metric]] {
        guard let stored = defaults.dictionary(forKey: AppPreferences.Keys.usageQuotaMetrics) as? [String: [String]] else {
            return [:]
        }
        return stored.reduce(into: [UsageProviderID: [Metric]]()) { result, entry in
            guard let providerID = UsageProviderID(rawValue: entry.key) else { return }
            result[providerID] = Array(entry.value.compactMap(Metric.init(rawValue:)).prefix(2))
        }
    }
}
