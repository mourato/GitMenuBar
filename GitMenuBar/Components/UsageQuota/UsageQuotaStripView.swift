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
        snapshots.filter { $0.primaryDisplayWindow != nil || !$0.modelWindows.isEmpty }
    }

    private func accessibilityValue(for snapshots: [UsageQuotaSnapshot]) -> String {
        // Mirrors UsageQuotaSummaryView: primary window, else the tightest model window.
        snapshots.compactMap { snapshot in
            let window = snapshot.primaryDisplayWindow
                ?? snapshot.modelWindows.min { $0.remainingPercent < $1.remainingPercent }
            return window.map {
                preferences.valueStyle == .left
                    ? "\(snapshot.displayName) \($0.remainingPercent) percent left"
                    : "\(snapshot.displayName) \(100 - $0.remainingPercent) percent used"
            }
        }
        .joined(separator: ", ")
    }
}

private struct UsageQuotaDetailsPopover: View {
    let snapshots: [UsageQuotaSnapshot]

    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @Environment(UsageQuotaStore.self) private var usageQuotaStore

    private var showUsed: Bool {
        preferences.valueStyle == .used
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                ForEach(snapshots) { snapshot in
                    UsageQuotaDotsCard(
                        providerID: snapshot.providerID,
                        displayName: snapshot.displayName,
                        pillText: UsageQuotaDotsCard.pillText(
                            plan: snapshot.planText,
                            intervalChip: snapshot.primaryDisplayWindow?.intervalChip,
                            resetCredits: snapshot.resetCreditsAvailable
                        ),
                        staleStyle: snapshot.isStale ? .button(snapshot) : .none,
                        rows: dotsRows(for: snapshot),
                        footnote: footnoteText(for: snapshot),
                        showUsed: showUsed
                    )
                    .padding(WorkbenchMetrics.compactSpacing)
                    .background(
                        RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .opacity(snapshot.isStale ? 0.72 : 1)
                }

                if let estimates = usageQuotaStore.costEstimates, !estimates.rows.isEmpty {
                    UsageQuotaCostDotsCard(estimates: estimates)
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

    private func dotsRows(for snapshot: UsageQuotaSnapshot) -> [UsageQuotaDotsCard.RowData] {
        var rows: [UsageQuotaDotsCard.RowData] = []
        if let window = snapshot.primaryDisplayWindow {
            let isSessionWindow = snapshot.sessionWindow == window
            rows.append(UsageQuotaDotsCard.RowData(
                title: UsageQuotaPace.rowTitle(isSessionWindow: isSessionWindow, window: window),
                countdown: UsageQuotaDotsCard.bareCountdown(until: window.resetAt),
                remainingPercent: window.remainingPercent,
                thresholds: isSessionWindow ? preferences.sessionWarningThresholds : preferences.weeklyWarningThresholds
            ))
        }
        if let weekly = secondaryWeeklyWindow(for: snapshot) {
            rows.append(UsageQuotaDotsCard.RowData(
                title: "Weekly",
                countdown: UsageQuotaDotsCard.bareCountdown(until: weekly.resetAt),
                remainingPercent: weekly.remainingPercent,
                thresholds: preferences.weeklyWarningThresholds
            ))
        }
        for window in snapshot.modelWindows {
            rows.append(UsageQuotaDotsCard.RowData(
                title: window.label,
                countdown: UsageQuotaDotsCard.bareCountdown(until: window.resetAt),
                remainingPercent: window.remainingPercent,
                thresholds: preferences.weeklyWarningThresholds
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
