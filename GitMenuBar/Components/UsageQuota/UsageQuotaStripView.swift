import AppKit
import SwiftUI

struct UsageQuotaStripView: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppPreferences.Keys.isUsageQuotaSectionCollapsed)
    private var isCollapsed = true

    init(defaults: UserDefaults = .standard) {
        _isCollapsed = AppStorage(
            wrappedValue: true,
            AppPreferences.Keys.isUsageQuotaSectionCollapsed,
            store: defaults
        )
    }

    var body: some View {
        let snapshots = usageQuotaStore.visibleSnapshots
        if usageQuotaStore.showAIUsageQuotas, !eligibleSnapshots(snapshots).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                WorkbenchSectionHeaderChrome(
                    title: "Quotas",
                    isCollapsed: $isCollapsed,
                    accessibilityLabel: "Quotas section",
                    accessibilityHintExpanded: "Expands quota details.",
                    accessibilityHintCollapsed: "Collapses quota details.",
                    includesTrailingInToggle: true
                ) { _ in
                    if isCollapsed {
                        UsageQuotaSummaryView(snapshots: eligibleSnapshots(snapshots))
                    }
                }

                if !isCollapsed {
                    expandedCards(snapshots: snapshots)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, WorkbenchMetrics.microSpacing)
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.settle, usesReducedMotion: reduceMotion),
                value: isCollapsed
            )
            // Quota cards are informational only — never imply clickability via the pointer.
            .onHover { hovering in
                if hovering {
                    NSCursor.arrow.push()
                } else {
                    NSCursor.pop()
                }
            }
            .task {
                usageQuotaStore.refresh(reason: .contentAppeared)
            }
        }
    }

    private func expandedCards(snapshots: [UsageQuotaSnapshot]) -> some View {
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
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.largeCornerRadius, style: .continuous)
                .strokeBorder(groupBorderColor, lineWidth: 1)
        }
    }

    private func eligibleSnapshots(_ snapshots: [UsageQuotaSnapshot]) -> [UsageQuotaSnapshot] {
        snapshots.filter { $0.primaryDisplayWindow != nil }
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
            } else if let creditsText = creditsLineText {
                Text(creditsText)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
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
            ProviderIconView(providerID: snapshot.providerID)

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

// MARK: - Previews

#Preview("Usage Quota Strip") {
    UsageQuotaStripPreviewHarness(
        collapsed: true,
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
        collapsed: true,
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
        collapsed: true,
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
        collapsed: true,
        snapshots: [
            PreviewUsageQuotaSnapshotFactory.cursor(
                remainingPercent: 33,
                resetInterval: 86400 * 20,
                isStale: true
            )
        ]
    )
}

#Preview("Usage Quota Strip – Collapsed Multi Provider") {
    UsageQuotaStripPreviewHarness(collapsed: true, snapshots: PreviewUsageQuotaSnapshotFactory.multiProvider)
}

#Preview("Usage Quota Strip – Expanded Multi Provider") {
    UsageQuotaStripPreviewHarness(collapsed: false, snapshots: PreviewUsageQuotaSnapshotFactory.multiProvider)
}

#Preview("Usage Quota Strip – No Eligible Snapshot") {
    UsageQuotaStripPreviewHarness(collapsed: true, snapshots: [])
}

private struct UsageQuotaStripPreviewHarness: View {
    let collapsed: Bool
    let snapshots: [UsageQuotaSnapshot]

    var body: some View {
        if let defaults = UserDefaults(suiteName: previewDefaultsName) {
            UsageQuotaStripView(defaults: defaults)
                .environmentObject(previewStore(defaults: defaults))
                .environmentObject(MainMenuPresentationModel())
                .frame(width: 380)
        }
    }

    private func previewStore(defaults: UserDefaults) -> UsageQuotaStore {
        defaults.removePersistentDomain(forName: previewDefaultsName)
        defaults.set(collapsed, forKey: AppPreferences.Keys.isUsageQuotaSectionCollapsed)
        let store = UsageQuotaStore(
            defaults: defaults,
            providers: snapshots.map { PreviewUsageQuotaProvider(snapshot: $0) }
        )
        store.showAIUsageQuotas = true
        return store
    }

    private var previewDefaultsName: String {
        "UsageQuotaStripPreview-\(snapshots.map(\.providerID.rawValue).joined(separator: "-"))"
    }
}

private enum PreviewUsageQuotaSnapshotFactory {
    static let multiProvider: [UsageQuotaSnapshot] = [
        codex(remainingPercent: 62, resetInterval: 8100, weeklyPercent: 88, resetCreditsAvailable: 2),
        cursor(remainingPercent: 41, resetInterval: 86400 * 12),
        openrouter(remainingPercent: 42, balanceText: "$12.50 left")
    ]

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

    static func openrouter(remainingPercent: Int, balanceText: String) -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: .openrouter,
            displayName: "OpenRouter",
            sessionWindow: UsageWindow(remainingPercent: remainingPercent, resetAt: nil, label: "Credits"),
            weeklyWindow: nil,
            creditValueText: balanceText,
            isAvailable: true,
            statusNote: "openrouter credits api"
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

    // swiftlint:disable:next async_without_await
    func fetchSnapshot() async -> UsageQuotaSnapshot {
        snapshot
    }
}
