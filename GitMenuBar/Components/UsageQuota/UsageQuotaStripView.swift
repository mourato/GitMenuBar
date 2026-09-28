import SwiftUI

struct UsageQuotaStripView: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore
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

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            headerRow

            if let window = snapshot.primaryDisplayWindow {
                UsageQuotaProgressBar(percent: window.remainingPercent)
                metaRow(for: window)
            } else if let creditsText = creditsLineText {
                Text(creditsText)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if let weekly = secondaryWeeklyWindow {
                weeklyRow(weekly)
            }

            if !snapshot.modelWindows.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(snapshot.modelWindows.enumerated()), id: \.offset) { _, window in
                        modelRow(window)
                    }
                }
            }
        }
        .opacity(snapshot.isStale ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
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

            if let window = snapshot.primaryDisplayWindow {
                UsageQuotaPercentLabel(percent: window.remainingPercent)
            }
        }
    }

    private func metaRow(for window: UsageWindow) -> some View {
        HStack(spacing: WorkbenchMetrics.sectionSpacing) {
            metaItem(
                systemImage: "gauge.with.dots.needle.33percent",
                text: UsageQuotaFormatting.resetCountdown(until: window.resetAt)
            )

            metaItem(
                systemImage: "clock",
                text: UsageQuotaFormatting.resetClockTime(until: window.resetAt)
            )

            Spacer(minLength: 0)

            if let creditsText = creditsLineText {
                Text(creditsText)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metaItem(systemImage: String, text: String) -> some View {
        HStack(spacing: WorkbenchMetrics.microSpacing) {
            Image(systemName: systemImage)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(text)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func weeklyRow(_ weekly: UsageWindow) -> some View {
        Text("\(weekly.intervalChip) \(weekly.remainingPercent)%")
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
    }

    private func modelRow(_ window: UsageWindow) -> some View {
        HStack(spacing: WorkbenchMetrics.microSpacing) {
            Text(window.label)
                .lineLimit(1)
            Spacer(minLength: WorkbenchMetrics.microSpacing)
            Text("\(window.remainingPercent)%")
                .monospacedDigit()
            Text(UsageQuotaFormatting.resetCountdown(until: window.resetAt))
                .monospacedDigit()
        }
        .font(WorkbenchTypography.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.label) \(window.remainingPercent) percent remaining")
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

private struct UsageQuotaPercentLabel: View {
    let percent: Int

    var body: some View {
        HStack(spacing: WorkbenchMetrics.microSpacing) {
            Circle()
                .fill(trafficLightColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text("\(percent)%")
                .font(WorkbenchTypography.captionStrong)
                .foregroundStyle(trafficLightColor)
        }
    }

    private var trafficLightColor: Color {
        UsageQuotaTrafficLightColor.swiftUI(for: percent)
    }
}

private struct UsageQuotaProgressBar: View {
    let percent: Int

    var body: some View {
        // Proportional meter fill needs measured width; static 4pt surface.
        // swiftlint:disable:next swiftui_geometry_reader
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))

                Capsule(style: .continuous)
                    .fill(UsageQuotaTrafficLightColor.swiftUI(for: percent))
                    .frame(width: max(0, geometry.size.width * CGFloat(percent) / 100))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
