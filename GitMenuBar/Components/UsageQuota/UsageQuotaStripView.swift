import SwiftUI

struct UsageQuotaStripView: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore
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
        snapshots.compactMap { snapshot in
            snapshot.primaryDisplayWindow.map {
                "\(snapshot.displayName) \($0.remainingPercent) percent remaining"
            }
        }
        .joined(separator: ", ")
    }
}

private struct UsageQuotaDetailsPopover: View {
    let snapshots: [UsageQuotaSnapshot]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                            .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                    }

                    UsageQuotaProviderCard(snapshot: snapshot)
                        .padding(.vertical, WorkbenchMetrics.compactSpacing)
                }
            }
            .padding(.horizontal, WorkbenchMetrics.compactSpacing)
            .padding(.vertical, WorkbenchMetrics.microSpacing)
        }
        .frame(width: 320)
        .frame(maxHeight: 420)
        .background(
            RoundedRectangle(cornerRadius: WorkbenchMetrics.largeCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.largeCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI usage quota details")
    }
}

private struct UsageQuotaProviderCard: View {
    let snapshot: UsageQuotaSnapshot

    @Environment(UsageQuotaPresentationPreferences.self) private var preferences

    private var showUsed: Bool {
        preferences.valueStyle == .used
    }

    private var rowStyle: UsageQuotaMeterRowStyle {
        UsageQuotaMeterRowStyle(
            titleFont: WorkbenchTypography.captionStrong,
            supportingFont: WorkbenchTypography.caption,
            primary: .primary,
            secondary: .secondary
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            headerRow

            if let window = snapshot.primaryDisplayWindow {
                meterRow(
                    title: UsageQuotaPace.rowTitle(isSessionWindow: isSessionWindow(window), window: window),
                    window: window,
                    thresholds: thresholds(for: window)
                )
                if let creditsText = creditsLineText {
                    Text(creditsText)
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let creditsText = creditsLineText {
                Text(creditsText)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if let weekly = secondaryWeeklyWindow {
                meterRow(
                    title: "Weekly",
                    window: weekly,
                    thresholds: preferences.weeklyWarningThresholds
                )
            }

            if !snapshot.modelWindows.isEmpty {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                    ForEach(Array(snapshot.modelWindows.enumerated()), id: \.offset) { _, window in
                        meterRow(
                            title: window.label,
                            window: window,
                            thresholds: preferences.weeklyWarningThresholds
                        )
                    }
                }
            }
        }
        .opacity(snapshot.isStale ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private func meterRow(title: String, window: UsageWindow, thresholds: [Int]) -> some View {
        UsageQuotaMeterRow(
            title: title,
            reading: UsageQuotaPace.reading(
                for: window,
                showUsed: showUsed,
                thresholds: thresholds,
                workdaysPerWeek: preferences.workdaysPerWeek,
                showPace: preferences.showsPace
            ),
            style: rowStyle,
            tint: UsageQuotaTrafficLightColor.swiftUI(for: window.remainingPercent),
            trackColor: Color.primary.opacity(0.08),
            barHeight: 4,
            accessibilityLabel: "\(snapshot.displayName) \(title)"
        )
    }

    private func isSessionWindow(_ window: UsageWindow) -> Bool {
        snapshot.sessionWindow == window
    }

    private func thresholds(for window: UsageWindow) -> [Int] {
        isSessionWindow(window) ? preferences.sessionWarningThresholds : preferences.weeklyWarningThresholds
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.compactSpacing) {
            ProviderIconView(providerID: snapshot.providerID)

            Text(snapshot.displayName)
                .font(WorkbenchTypography.body)
                .foregroundStyle(snapshot.isStale ? .secondary : .primary)

            if let window = snapshot.primaryDisplayWindow {
                Text(window.intervalChip)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .accessibilityHidden(true)
            }

            if snapshot.isStale {
                StaleQuotaInfoButton(snapshot: snapshot)
            }

            Spacer(minLength: 0)
        }
    }

    private var secondaryWeeklyWindow: UsageWindow? {
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

    private var creditsLineText: String? {
        if let resetCreditsAvailable = snapshot.resetCreditsAvailable {
            return resetCreditsLabel(resetCreditsAvailable)
        }
        return snapshot.creditValueText
    }

    private func resetCreditsLabel(_ count: Int) -> String {
        count == 1 ? "1 reset" : "\(count) resets"
    }

    private var accessibilityLabel: String {
        guard let window = snapshot.primaryDisplayWindow else {
            return "\(snapshot.displayName) usage unavailable"
        }
        return "\(snapshot.displayName) \(window.intervalChip) usage \(window.remainingPercent) percent remaining"
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let window = snapshot.primaryDisplayWindow {
            let reading = UsageQuotaPace.reading(
                for: window,
                showUsed: showUsed,
                thresholds: thresholds(for: window),
                workdaysPerWeek: preferences.workdaysPerWeek,
                showPace: preferences.showsPace
            )
            parts.append(reading.percentText)
            if let paceLeft = reading.paceLeftText {
                parts.append(paceLeft)
            }
            if let paceRight = reading.paceRightText {
                parts.append(paceRight)
            }
            parts.append("resets in \(UsageQuotaFormatting.resetCountdown(until: window.resetAt))")
            let clockTime = UsageQuotaFormatting.resetClockTime(until: window.resetAt)
            if clockTime != "—" {
                parts.append("next reset at \(clockTime)")
            }
        }
        if let weekly = secondaryWeeklyWindow {
            parts.append("\(weekly.intervalChip) \(weekly.remainingPercent) percent")
        }
        for window in snapshot.modelWindows {
            parts.append("\(window.label) \(window.remainingPercent) percent")
        }
        if let resetCreditsAvailable = snapshot.resetCreditsAvailable {
            parts.append(resetCreditsLabel(resetCreditsAvailable))
        } else if let creditValueText = snapshot.creditValueText {
            parts.append(creditValueText)
        }
        if snapshot.isStale {
            parts.append("stale")
        }
        if let note = snapshot.statusNote {
            parts.append(note)
        }
        return parts.joined(separator: ", ")
    }
}
