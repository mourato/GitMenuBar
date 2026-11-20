import AppKit
import SwiftUI

struct UsageQuotaMenuView: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences

    static let width: CGFloat = 320

    var body: some View {
        let snapshots = orderedSnapshots
        let showUsed = preferences.valueStyle == .used
        VStack(alignment: .leading, spacing: 12) {
            if snapshots.isEmpty, usageQuotaStore.costEstimates == nil {
                Text("No usage figures available")
                    .font(UsageQuotaMenuTypography.supporting)
                    .foregroundStyle(UsageQuotaMenuInk.secondary)
                    .padding(.vertical, 10)
            } else {
                if !snapshots.isEmpty {
                    UsageQuotaValueStyleCaption(showUsed: showUsed)
                }
                ForEach(snapshots) { snapshot in
                    providerSection(snapshot)
                }
                if let estimates = usageQuotaStore.costEstimates, !estimates.rows.isEmpty {
                    UsageQuotaCostCard(estimates: estimates)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(UsageQuotaMenuInk.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(UsageQuotaMenuInk.border, lineWidth: 0.5)
                        )
                }
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .fixedSize()
    }

    private var orderedSnapshots: [UsageQuotaSnapshot] {
        let snapshotsByProvider = Dictionary(uniqueKeysWithValues: usageQuotaStore.visibleSnapshots.map { ($0.providerID, $0) })
        return preferences.orderedProviderIDs.compactMap { snapshotsByProvider[$0] }
    }

    private func providerSection(_ snapshot: UsageQuotaSnapshot) -> some View {
        UsageQuotaLineCard(
            providerID: snapshot.providerID,
            displayName: snapshot.displayName,
            pillText: UsageQuotaLineCard.pillText(
                plan: snapshot.planText,
                resetCredits: creditsMetricSelected(for: snapshot) ? snapshot.resetCreditsAvailable : nil
            ),
            staleStyle: snapshot.isStale ? .text : .none,
            rows: quotaRows(for: snapshot),
            footnote: footnoteText(for: snapshot),
            showUsed: preferences.valueStyle == .used,
            showsPace: preferences.showsPace,
            workdaysPerWeek: preferences.workdaysPerWeek,
            showsWorkdayTicks: preferences.workdayTickAppearance == .subtle
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(UsageQuotaMenuInk.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(UsageQuotaMenuInk.border, lineWidth: 0.5)
        )
        .opacity(snapshot.isStale ? 0.72 : 1)
        .accessibilityElement(children: .contain)
    }

    private func quotaRows(for snapshot: UsageQuotaSnapshot) -> [UsageQuotaLineCard.RowData] {
        var rows: [UsageQuotaLineCard.RowData] = []
        if let sessionWindow = snapshot.sessionWindow {
            rows.append(UsageQuotaLineCard.RowData(
                title: UsageQuotaPace.rowTitle(isSessionWindow: true, window: sessionWindow),
                window: sessionWindow,
                thresholds: preferences.sessionWarningThresholds,
                kind: .session
            ))
        }
        if let weeklyWindow = snapshot.weeklyWindow {
            rows.append(UsageQuotaLineCard.RowData(
                title: UsageQuotaPace.rowTitle(isSessionWindow: false, window: weeklyWindow),
                window: weeklyWindow,
                thresholds: preferences.weeklyWarningThresholds,
                kind: .weekly
            ))
        }
        if let monthlyWindow = snapshot.tertiaryMonthlyWindow {
            rows.append(UsageQuotaLineCard.RowData(
                title: monthlyWindow.label,
                window: monthlyWindow,
                thresholds: preferences.weeklyWarningThresholds,
                kind: .model
            ))
        }
        for window in snapshot.modelWindows {
            rows.append(UsageQuotaLineCard.RowData(
                title: window.label,
                window: window,
                thresholds: preferences.weeklyWarningThresholds,
                kind: .model
            ))
        }
        return rows
    }

    private func footnoteText(for snapshot: UsageQuotaSnapshot) -> String? {
        guard creditsMetricSelected(for: snapshot), snapshot.resetCreditsAvailable == nil else { return nil }
        return snapshot.creditValueText
    }

    private func creditsMetricSelected(for snapshot: UsageQuotaSnapshot) -> Bool {
        UsageQuotaMenuPresentation.value(
            for: .credits,
            snapshot: snapshot,
            valueStyle: preferences.valueStyle
        ) != nil
    }
}

struct UsageQuotaMenuBarGroup: Equatable, Identifiable {
    let providerID: UsageProviderID
    let values: [String]
    let fractions: [Double]
    let readings: [UsageQuotaMenuBarReading]

    var id: UsageProviderID {
        providerID
    }
}

struct UsageQuotaMenuBarReading: Equatable, Sendable {
    let compactValue: String
    let fraction: Double?
    let pacePercent: Double?
    let paceDeficit: Bool
}

enum UsageQuotaMenuPresentation {
    @MainActor
    static func groups(
        snapshots: [UsageQuotaSnapshot],
        preferences: UsageQuotaPresentationPreferences,
        now: Date = Date()
    ) -> [UsageQuotaMenuBarGroup] {
        let snapshotsByProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.providerID, $0) })
        return preferences.orderedProviderIDs.compactMap { providerID in
            let selectedMetrics = preferences.selectedMetrics(for: providerID)
            guard let snapshot = snapshotsByProvider[providerID],
                  isEligible(snapshot: snapshot, selectedMetrics: selectedMetrics)
            else { return nil }
            var readings: [UsageQuotaMenuBarReading] = []
            for metric in selectedMetrics {
                guard let reading = value(for: metric, snapshot: snapshot, valueStyle: preferences.valueStyle) else { continue }
                readings.append(barReading(
                    compactValue: reading.compactValue,
                    window: reading.window,
                    preferences: preferences,
                    now: now
                ))
            }
            if !readings.isEmpty || (!selectedMetrics.isEmpty && !snapshot.modelWindows.isEmpty) {
                for modelWindow in snapshot.modelWindows.prefix(2) {
                    let windowReading = reading(
                        for: modelWindow,
                        kind: .model,
                        valueStyle: preferences.valueStyle
                    )
                    readings.append(barReading(
                        compactValue: "\(modelWindow.label) \(windowReading.compactValue)",
                        window: modelWindow,
                        preferences: preferences,
                        now: now
                    ))
                }
            }
            guard !readings.isEmpty else { return nil }
            return UsageQuotaMenuBarGroup(
                providerID: providerID,
                values: readings.map(\.compactValue),
                fractions: readings.compactMap(\.fraction),
                readings: readings
            )
        }
    }

    @MainActor
    private static func barReading(
        compactValue: String,
        window: UsageWindow?,
        preferences: UsageQuotaPresentationPreferences,
        now: Date
    ) -> UsageQuotaMenuBarReading {
        guard let window else {
            return UsageQuotaMenuBarReading(
                compactValue: compactValue,
                fraction: nil,
                pacePercent: nil,
                paceDeficit: false
            )
        }
        let windowReading = UsageQuotaPace.reading(
            for: window,
            showUsed: preferences.valueStyle == .used,
            thresholds: [],
            workdaysPerWeek: preferences.workdaysPerWeek,
            showPace: preferences.showsPace,
            now: now
        )
        return UsageQuotaMenuBarReading(
            compactValue: compactValue,
            fraction: windowReading.fillPercent / 100,
            pacePercent: windowReading.pacePercent,
            paceDeficit: windowReading.paceDeficit
        )
    }

    static func isEligible(
        snapshot: UsageQuotaSnapshot,
        selectedMetrics: [UsageQuotaPresentationPreferences.Metric]
    ) -> Bool {
        guard snapshot.weeklyWindow?.remainingPercent != 0 else { return false }
        if selectedMetrics.contains(where: { value(for: $0, snapshot: snapshot, valueStyle: .left) != nil }) {
            return true
        }
        return !selectedMetrics.isEmpty && !snapshot.modelWindows.isEmpty
    }

    static func value(
        for metric: UsageQuotaPresentationPreferences.Metric,
        snapshot: UsageQuotaSnapshot,
        valueStyle: UsageQuotaPresentationPreferences.ValueStyle
    ) -> UsageQuotaMenuReading? {
        switch metric {
        case .session:
            guard let window = snapshot.sessionWindow else { return nil }
            return reading(for: window, kind: .session, valueStyle: valueStyle)
        case .weekly:
            guard let window = snapshot.weeklyWindow else { return nil }
            return reading(for: window, kind: .weekly, valueStyle: valueStyle)
        case .monthly:
            guard let window = snapshot.tertiaryMonthlyWindow else { return nil }
            return reading(for: window, kind: .model, valueStyle: valueStyle)
        case .credits:
            if let resetCreditsAvailable = snapshot.resetCreditsAvailable {
                let label = resetCreditsAvailable == 1 ? "1 reset" : "\(resetCreditsAvailable) resets"
                return UsageQuotaMenuReading(label: "Credits", value: label, compactValue: label, fraction: nil, window: nil)
            }
            guard let creditValueText = snapshot.creditValueText else { return nil }
            return UsageQuotaMenuReading(label: "Credits", value: creditValueText, compactValue: creditValueText, fraction: nil, window: nil)
        }
    }

    fileprivate static func reading(
        for window: UsageWindow,
        kind: UsageQuotaWindowKind,
        valueStyle: UsageQuotaPresentationPreferences.ValueStyle
    ) -> UsageQuotaMenuReading {
        let showUsed = valueStyle == .used
        let percent = UsageQuotaFormatting.displayPercent(
            remainingPercent: window.remainingPercent,
            showUsed: showUsed
        )
        let fraction = Double(percent) / 100
        return UsageQuotaMenuReading(
            label: window.label,
            value: UsageQuotaFormatting.displayValueText(
                remainingPercent: window.remainingPercent,
                kind: kind,
                showUsed: showUsed
            ),
            compactValue: UsageQuotaFormatting.compactDisplayValueText(
                remainingPercent: window.remainingPercent,
                kind: kind,
                showUsed: showUsed
            ),
            fraction: fraction,
            window: window
        )
    }
}

struct UsageQuotaMenuReading {
    let label: String
    let value: String
    let compactValue: String
    let fraction: Double?
    let window: UsageWindow?
}

private enum UsageQuotaMenuTypography {
    static let supporting = Font(NSFont.menuFont(ofSize: max(10, NSFont.menuFont(ofSize: 0).pointSize - 1)))
}

private enum UsageQuotaMenuInk {
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let card = Color(nsColor: .quaternarySystemFill)
    static let border = Color(nsColor: .separatorColor)
}

#if DEBUG
    #Preview("Usage Quota Menu") {
        UsageQuotaMenuPreviewHarness()
    }

    #Preview("Usage Quota Menu – Circular") {
        UsageQuotaMenuPreviewHarness(meterStyle: .circular)
    }

    #Preview("Usage Quota Menu – Claude Models") {
        UsageQuotaMenuPreviewHarness(snapshots: [UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            sessionWindow: UsageWindow(
                remainingPercent: 77,
                resetAt: Date().addingTimeInterval(8100),
                label: "5h",
                durationSeconds: 18000
            ),
            weeklyWindow: UsageWindow(
                remainingPercent: 58,
                resetAt: Date().addingTimeInterval(86400 * 3),
                label: "7d",
                durationSeconds: 604_800
            ),
            modelWindows: [
                UsageWindow(
                    remainingPercent: 88,
                    resetAt: Date().addingTimeInterval(86400 * 3),
                    label: "Sonnet",
                    durationSeconds: 604_800
                ),
                UsageWindow(
                    remainingPercent: 32,
                    resetAt: Date().addingTimeInterval(86400 * 3),
                    label: "Opus",
                    durationSeconds: 604_800
                )
            ],
            isAvailable: true
        )])
    }

    #Preview("Usage Quota Menu – Issue 19 Fixture") {
        UsageQuotaMenuPreviewHarness(snapshots: PreviewUsageQuotaSnapshotFactory.issueFixture)
    }

    private struct UsageQuotaMenuPreviewHarness: View {
        @State private var store: UsageQuotaStore
        @State private var preferences: UsageQuotaPresentationPreferences

        init(
            snapshots: [UsageQuotaSnapshot]? = nil,
            meterStyle: UsageQuotaPresentationPreferences.MeterStyle = .text
        ) {
            let snapshots = snapshots ?? [
                UsageQuotaSnapshot(
                    providerID: .codex,
                    displayName: "Codex",
                    sessionWindow: UsageWindow(
                        remainingPercent: 62,
                        resetAt: Date().addingTimeInterval(8100),
                        label: "5h",
                        durationSeconds: 18000
                    ),
                    weeklyWindow: UsageWindow(
                        remainingPercent: 88,
                        resetAt: Date().addingTimeInterval(86400 * 3),
                        label: "7d",
                        durationSeconds: 604_800
                    ),
                    creditValueText: "12.50 credits",
                    isAvailable: true
                )
            ]
            let name = "UsageQuotaMenuPreview-\(meterStyle.rawValue)-\(snapshots.map(\.providerID.rawValue).joined(separator: "-"))"
            let defaults = UserDefaults(suiteName: name) ?? .standard
            defaults.removePersistentDomain(forName: name)
            defaults.set(true, forKey: AppPreferences.Keys.showAIUsageQuotas)
            let snapshotStore = UsageQuotaSnapshotStore(defaults: defaults)
            for snapshot in snapshots {
                snapshotStore.save(snapshot)
            }
            _store = State(wrappedValue: UsageQuotaStore(
                defaults: defaults,
                snapshotStore: snapshotStore,
                providers: snapshots.map { UsageQuotaPreviewProvider(snapshot: $0) }
            ))
            let preferences = UsageQuotaPresentationPreferences(defaults: defaults, keyStore: InMemoryAIAPIKeyStore())
            preferences.meterStyle = meterStyle
            _preferences = State(wrappedValue: preferences)
        }

        var body: some View {
            UsageQuotaMenuView()
                .environment(store)
                .environment(preferences)
        }
    }

    private struct UsageQuotaPreviewProvider: UsageQuotaProviding {
        let id: UsageProviderID
        let snapshot: UsageQuotaSnapshot

        init(snapshot: UsageQuotaSnapshot) {
            id = snapshot.providerID
            self.snapshot = snapshot
        }

        // swiftlint:disable:next async_without_await
        func fetchSnapshot() async -> UsageQuotaSnapshot {
            snapshot
        }
    }
#endif
