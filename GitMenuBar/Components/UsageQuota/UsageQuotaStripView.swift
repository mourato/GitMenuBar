import SwiftUI

struct UsageQuotaStripView: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore

    var body: some View {
        let snapshots = usageQuotaStore.visibleSnapshots
        if usageQuotaStore.showAIUsageQuotas, !snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(snapshots) { snapshot in
                    UsageQuotaProviderRow(snapshot: snapshot)
                }
            }
            .padding(.horizontal, MacChromeMetrics.windowPadding)
            .padding(.vertical, MacChromeMetrics.compactSpacing)
            .task {
                usageQuotaStore.refresh(reason: .contentAppeared)
            }
        }
    }
}

private struct UsageQuotaProviderRow: View {
    let snapshot: UsageQuotaSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacChromeMetrics.compactSpacing) {
            Text(snapshot.displayName)
                .font(MacChromeTypography.captionStrong)
                .foregroundStyle(snapshot.isStale ? .secondary : .primary)
                .frame(minWidth: 52, alignment: .leading)

            if let window = snapshot.primaryDisplayWindow {
                Text(window.intervalChip)
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .accessibilityHidden(true)

                UsageQuotaPercentBadge(
                    percent: window.remainingPercent,
                    resetAt: window.resetAt
                )
            }

            Spacer(minLength: 0)

            if let weekly = snapshot.weeklyWindow,
               snapshot.primaryDisplayWindow?.label != weekly.label
               || snapshot.primaryDisplayWindow?.remainingPercent != weekly.remainingPercent {
                Text("\(weekly.intervalChip) \(weekly.remainingPercent)%")
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if let resetCreditsAvailable = snapshot.resetCreditsAvailable {
                Text(resetCreditsLabel(resetCreditsAvailable))
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            } else if let creditValueText = snapshot.creditValueText {
                Text(creditValueText)
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(snapshot.isStale ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
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
        }
        if let weekly = snapshot.weeklyWindow {
            parts.append("\(weekly.intervalChip) \(weekly.remainingPercent) percent")
        }
        if let resetCreditsAvailable = snapshot.resetCreditsAvailable {
            parts.append(resetCreditsLabel(resetCreditsAvailable))
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

private struct UsageQuotaPercentBadge: View {
    let percent: Int
    let resetAt: Date?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(trafficLightColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text("\(percent)%")
                .font(MacChromeTypography.captionStrong)
                .foregroundStyle(trafficLightColor)

            Text(UsageQuotaFormatting.resetCountdown(until: resetAt))
                .font(MacChromeTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var trafficLightColor: Color {
        switch UsageQuotaFormatting.trafficLightColor(for: percent) {
        case .green:
            return .green
        case .amber:
            return .orange
        case .red:
            return .red
        }
    }
}

#Preview("Usage Quota Strip") {
    let defaults = UserDefaults(suiteName: "UsageQuotaStripPreview")!
    defaults.removePersistentDomain(forName: "UsageQuotaStripPreview")
    let snapshot = UsageQuotaSnapshot(
        providerID: .codex,
        displayName: "Codex",
        sessionWindow: UsageWindow(
            remainingPercent: 62,
            resetAt: Date().addingTimeInterval(8100),
            label: "5h",
            durationSeconds: 5 * 3600
        ),
        weeklyWindow: UsageWindow(
            remainingPercent: 88,
            resetAt: Date().addingTimeInterval(86400 * 3),
            label: "7d",
            durationSeconds: 7 * 86400
        ),
        resetCreditsAvailable: 2,
        isAvailable: true,
        statusNote: "chatgpt usage api"
    )
    let store = UsageQuotaStore(
        defaults: defaults,
        providers: [PreviewUsageQuotaProvider(snapshot: snapshot)]
    )
    store.showAIUsageQuotas = true

    return UsageQuotaStripView()
        .environmentObject(store)
        .frame(width: 380)
}

#Preview("Usage Quota Strip – Stale") {
    let defaults = UserDefaults(suiteName: "UsageQuotaStripStalePreview")!
    defaults.removePersistentDomain(forName: "UsageQuotaStripStalePreview")
    let snapshot = UsageQuotaSnapshot(
        providerID: .cursor,
        displayName: "Cursor",
        sessionWindow: UsageWindow(
            remainingPercent: 33,
            resetAt: Date().addingTimeInterval(86400 * 20),
            label: "Plan",
            durationSeconds: 30 * 86400
        ),
        weeklyWindow: nil,
        isAvailable: true,
        isStale: true,
        statusNote: "cursor usage-summary api"
    )
    let store = UsageQuotaStore(
        defaults: defaults,
        providers: [PreviewUsageQuotaProvider(snapshot: snapshot)]
    )
    store.showAIUsageQuotas = true

    return UsageQuotaStripView()
        .environmentObject(store)
        .frame(width: 380)
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
