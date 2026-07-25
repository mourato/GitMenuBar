import SwiftUI

struct UsageQuotaStripView: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let snapshots = usageQuotaStore.visibleSnapshots
        if usageQuotaStore.showAIUsageQuotas, !snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                    }

                    UsageQuotaProviderCard(snapshot: snapshot)
                }
            }
            .padding(WorkbenchMetrics.compactSpacing)
            .overlay {
                RoundedRectangle(cornerRadius: WorkbenchMetrics.largeCornerRadius, style: .continuous)
                    .strokeBorder(groupBorderColor, lineWidth: 1)
            }
            .padding(.vertical, WorkbenchMetrics.compactSpacing)
            .task {
                usageQuotaStore.refresh(reason: .contentAppeared)
            }
        }
    }

    private var groupBorderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12)
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
            }

            if let weekly = secondaryWeeklyWindow {
                weeklyRow(weekly)
            }
        }
        .opacity(snapshot.isStale ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.compactSpacing) {
            Text(snapshot.displayName)
                .font(WorkbenchTypography.captionStrong)
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

    private var secondaryWeeklyWindow: UsageWindow? {
        guard let weekly = snapshot.weeklyWindow,
              let primary = snapshot.primaryDisplayWindow else {
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

private enum UsageQuotaTrafficLightColor {
    static func swiftUI(for remainingPercent: Int) -> Color {
        switch UsageQuotaFormatting.trafficLightColor(for: remainingPercent) {
        case .green:
            return .green
        case .amber:
            return .orange
        case .red:
            return .red
        }
    }
}

// MARK: - Previews

#Preview("Usage Quota Strip") {
    UsageQuotaStripPreviewHarness(
        snapshots: [
            PreviewUsageQuotaSnapshotFactory.codex(
                remainingPercent: 62,
                resetInterval: 8100,
                weeklyPercent: 88,
                resetCreditsAvailable: 2
            )
        ]
    )
}

#Preview("Usage Quota Strip – High") {
    UsageQuotaStripPreviewHarness(
        snapshots: [
            PreviewUsageQuotaSnapshotFactory.codex(
                remainingPercent: 95,
                resetInterval: 3600,
                weeklyPercent: 95
            )
        ]
    )
}

#Preview("Usage Quota Strip – Low") {
    UsageQuotaStripPreviewHarness(
        snapshots: [
            PreviewUsageQuotaSnapshotFactory.cursor(
                remainingPercent: 8,
                resetInterval: 7200
            )
        ]
    )
}

#Preview("Usage Quota Strip – Stale") {
    UsageQuotaStripPreviewHarness(
        snapshots: [
            PreviewUsageQuotaSnapshotFactory.cursor(
                remainingPercent: 33,
                resetInterval: 86400 * 20,
                isStale: true
            )
        ]
    )
}

#Preview("Usage Quota Strip – Dual Provider") {
    UsageQuotaStripPreviewHarness(
        snapshots: [
            PreviewUsageQuotaSnapshotFactory.codex(
                remainingPercent: 62,
                resetInterval: 8100,
                weeklyPercent: 88,
                resetCreditsAvailable: 2
            ),
            PreviewUsageQuotaSnapshotFactory.cursor(
                remainingPercent: 41,
                resetInterval: 86400 * 12
            )
        ]
    )
}

private struct UsageQuotaStripPreviewHarness: View {
    let snapshots: [UsageQuotaSnapshot]

    var body: some View {
        let defaults = UserDefaults(suiteName: previewDefaultsName)!
        defaults.removePersistentDomain(forName: previewDefaultsName)
        let store = UsageQuotaStore(
            defaults: defaults,
            providers: snapshots.map { PreviewUsageQuotaProvider(snapshot: $0) }
        )
        store.showAIUsageQuotas = true

        return UsageQuotaStripView()
            .environmentObject(store)
            .frame(width: 380)
    }

    private var previewDefaultsName: String {
        "UsageQuotaStripPreview-\(snapshots.map(\.providerID.rawValue).joined(separator: "-"))"
    }
}

private enum PreviewUsageQuotaSnapshotFactory {
    static func codex(
        remainingPercent: Int,
        resetInterval: TimeInterval,
        weeklyPercent: Int? = nil,
        resetCreditsAvailable: Int? = nil,
        isStale: Bool = false
    ) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: UsageWindow(
                remainingPercent: remainingPercent,
                resetAt: Date().addingTimeInterval(resetInterval),
                label: "5h",
                durationSeconds: 5 * 3600
            ),
            weeklyWindow: weeklyPercent.map { percent in
                UsageWindow(
                    remainingPercent: percent,
                    resetAt: Date().addingTimeInterval(86400 * 3),
                    label: "7d",
                    durationSeconds: 7 * 86400
                )
            },
            resetCreditsAvailable: resetCreditsAvailable,
            isAvailable: true,
            isStale: isStale,
            statusNote: "chatgpt usage api"
        )
    }

    static func cursor(
        remainingPercent: Int,
        resetInterval: TimeInterval,
        isStale: Bool = false
    ) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: .cursor,
            displayName: "Cursor",
            sessionWindow: UsageWindow(
                remainingPercent: remainingPercent,
                resetAt: Date().addingTimeInterval(resetInterval),
                label: "Plan",
                durationSeconds: 30 * 86400
            ),
            weeklyWindow: nil,
            isAvailable: true,
            isStale: isStale,
            statusNote: "cursor usage-summary api"
        )
    }
}

private struct PreviewUsageQuotaProvider: UsageQuotaProviding {
    let id: UsageProviderID
    let snapshot: UsageQuotaSnapshot

    init(snapshot: UsageQuotaSnapshot) {
        id = snapshot.providerID
        self.snapshot = snapshot
    }

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        snapshot
    }
}
