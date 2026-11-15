import SwiftUI

struct UsageQuotaStripView: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @State private var isPopoverPresented = false

    var body: some View {
        let snapshots = usageQuotaStore.visibleSnapshots
        if usageQuotaStore.showAIUsageQuotas, !eligibleSnapshots(snapshots).isEmpty {
            Button {
                isPopoverPresented.toggle()
            } label: {
                UsageQuotaSummaryView(snapshots: snapshots)
                    .padding(.horizontal, WorkbenchMetrics.microSpacing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .frame(minHeight: WorkbenchMetrics.iconHitTarget)
            .help("Show AI usage quotas")
            .accessibilityLabel("AI usage quotas")
            .accessibilityValue(accessibilityValue(for: snapshots))
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                UsageQuotaDetailsPopover(snapshots: snapshots)
            }
            .task {
                usageQuotaStore.refresh(reason: .contentAppeared)
            }
        }
    }

    private func eligibleSnapshots(_ snapshots: [UsageQuotaSnapshot]) -> [UsageQuotaSnapshot] {
        snapshots.filter { $0.primaryDisplayWindow != nil || $0.tertiaryMonthlyWindow != nil || !$0.modelWindows.isEmpty }
    }

    private func accessibilityValue(for snapshots: [UsageQuotaSnapshot]) -> String {
        // Same critical-window resolution as the footer summary items, so the
        // strip value never names a different window than the drawn meter.
        snapshots.compactMap { snapshot in
            UsageQuotaSummaryResolution.resolve(
                snapshot: snapshot,
                sessionThresholds: preferences.sessionWarningThresholds,
                weeklyThresholds: preferences.weeklyWarningThresholds
            ).map { resolved in
                let reading = UsageQuotaPace.reading(
                    for: resolved.window,
                    showUsed: preferences.valueStyle == .used,
                    thresholds: [],
                    workdaysPerWeek: preferences.workdaysPerWeek,
                    showPace: preferences.showsPace
                )
                return UsageQuotaSummaryResolution.describe(
                    displayName: snapshot.displayName,
                    resolution: resolved,
                    reading: reading,
                    isStale: snapshot.isStale
                )
            }
        }
        .joined(separator: ", ")
    }
}

struct UsageQuotaDetailsPopover: View {
    let snapshots: [UsageQuotaSnapshot]

    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @Environment(UsageQuotaStore.self) private var usageQuotaStore

    private var showUsed: Bool {
        preferences.valueStyle == .used
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                if !snapshots.isEmpty {
                    UsageQuotaValueStyleCaption(showUsed: showUsed)
                }
                ForEach(snapshots) { snapshot in
                    UsageQuotaLineCard(
                        providerID: snapshot.providerID,
                        displayName: snapshot.displayName,
                        pillText: UsageQuotaLineCard.pillText(
                            plan: snapshot.planText,
                            resetCredits: snapshot.resetCreditsAvailable
                        ),
                        staleStyle: snapshot.isStale ? .button(snapshot) : .none,
                        rows: quotaRows(for: snapshot),
                        footnote: footnoteText(for: snapshot),
                        showUsed: showUsed,
                        showsPace: preferences.showsPace,
                        workdaysPerWeek: preferences.workdaysPerWeek,
                        showsWorkdayTicks: preferences.workdayTickAppearance == .subtle
                    )
                    .padding(WorkbenchMetrics.compactSpacing)
                    .background(
                        RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .opacity(snapshot.isStale ? 0.72 : 1)
                }

                if let estimates = usageQuotaStore.costEstimates, !estimates.rows.isEmpty {
                    UsageQuotaCostCard(estimates: estimates)
                        .padding(WorkbenchMetrics.compactSpacing)
                        .background(
                            RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                }
            }
            .padding(WorkbenchMetrics.compactSpacing)
        }
        .frame(width: 340)
        .frame(maxHeight: 460)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI usage quota details")
    }

    private func quotaRows(for snapshot: UsageQuotaSnapshot) -> [UsageQuotaLineCard.RowData] {
        var rows: [UsageQuotaLineCard.RowData] = []
        if let window = snapshot.primaryDisplayWindow {
            let isSessionWindow = snapshot.sessionWindow == window
            rows.append(UsageQuotaLineCard.RowData(
                title: UsageQuotaPace.rowTitle(isSessionWindow: isSessionWindow, window: window),
                window: window,
                thresholds: isSessionWindow ? preferences.sessionWarningThresholds : preferences.weeklyWarningThresholds,
                kind: isSessionWindow ? .session : .weekly
            ))
        }
        if let weekly = secondaryWeeklyWindow(for: snapshot) {
            rows.append(UsageQuotaLineCard.RowData(
                title: "Weekly",
                window: weekly,
                thresholds: preferences.weeklyWarningThresholds,
                kind: .weekly
            ))
        }
        if let monthly = snapshot.tertiaryMonthlyWindow {
            rows.append(UsageQuotaLineCard.RowData(
                title: monthly.label,
                window: monthly,
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

    private func secondaryWeeklyWindow(for snapshot: UsageQuotaSnapshot) -> UsageWindow? {
        guard let weekly = snapshot.weeklyWindow,
              let primary = snapshot.primaryDisplayWindow
        else {
            return nil
        }
        if primary.label != weekly.label || primary.remainingPercent != weekly.remainingPercent {
            return weekly
        }
        return nil
    }

    private func footnoteText(for snapshot: UsageQuotaSnapshot) -> String? {
        guard snapshot.resetCreditsAvailable == nil else { return nil }
        return snapshot.creditValueText
    }
}

#if DEBUG
    #Preview("Usage Quota Details Popover") {
        UsageQuotaDetailsPopoverPreviewHarness()
    }

    private struct UsageQuotaDetailsPopoverPreviewHarness: View {
        @State private var store: UsageQuotaStore
        @State private var preferences: UsageQuotaPresentationPreferences

        init() {
            let name = "UsageQuotaDetailsPopoverPreview"
            let defaults = UserDefaults(suiteName: name) ?? .standard
            defaults.removePersistentDomain(forName: name)
            defaults.set(true, forKey: AppPreferences.Keys.showAIUsageQuotas)
            let snapshotStore = UsageQuotaSnapshotStore(defaults: defaults)
            let snapshots = PreviewUsageQuotaSnapshotFactory.issueFixture
            for snapshot in snapshots {
                snapshotStore.save(snapshot)
            }
            _store = State(wrappedValue: UsageQuotaStore(
                defaults: defaults,
                snapshotStore: snapshotStore,
                providers: snapshots.map { PreviewUsageQuotaProvider(snapshot: $0) }
            ))
            _preferences = State(wrappedValue: UsageQuotaPresentationPreferences(
                defaults: defaults,
                keyStore: InMemoryAIAPIKeyStore()
            ))
        }

        var body: some View {
            UsageQuotaDetailsPopover(snapshots: PreviewUsageQuotaSnapshotFactory.issueFixture)
                .environment(store)
                .environment(preferences)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
