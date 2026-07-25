import SwiftUI

struct UsageQuotaStripView: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore

    var body: some View {
        let snapshots = usageQuotaStore.visibleSnapshots
        if usageQuotaStore.showAIUsageQuotas, !snapshots.isEmpty {
            VStack(alignment: .leading, spacing: MacChromeMetrics.compactSpacing) {
                ForEach(snapshots) { snapshot in
                    UsageQuotaProviderRow(snapshot: snapshot)
                }
            }
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

            if let session = snapshot.sessionWindow {
                UsageQuotaPercentBadge(
                    percent: session.remainingPercent,
                    resetAt: session.resetAt
                )
            }

            Spacer(minLength: 0)

            if let weekly = snapshot.weeklyWindow {
                Text("Weekly \(weekly.remainingPercent)%")
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if let creditValueText = snapshot.creditValueText {
                Text(creditValueText)
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, MacChromeMetrics.panelPadding)
        .padding(.vertical, MacChromeMetrics.compactSpacing)
        .opacity(snapshot.isStale ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityLabel: String {
        guard let session = snapshot.sessionWindow else {
            return "\(snapshot.displayName) usage unavailable"
        }
        return "\(snapshot.displayName) usage \(session.remainingPercent) percent remaining"
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let session = snapshot.sessionWindow {
            parts.append("resets in \(UsageQuotaFormatting.resetCountdown(until: session.resetAt))")
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
        sessionWindow: UsageWindow(remainingPercent: 62, resetAt: Date().addingTimeInterval(8100), label: "Session"),
        weeklyWindow: UsageWindow(remainingPercent: 88, resetAt: Date().addingTimeInterval(86400 * 3), label: "Weekly"),
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
        .padding()
        .frame(width: 380)
}

#Preview("Usage Quota Strip – Stale") {
    let defaults = UserDefaults(suiteName: "UsageQuotaStripStalePreview")!
    defaults.removePersistentDomain(forName: "UsageQuotaStripStalePreview")
    let snapshot = UsageQuotaSnapshot(
        providerID: .codex,
        displayName: "Codex",
        sessionWindow: UsageWindow(remainingPercent: 12, resetAt: Date().addingTimeInterval(900), label: "Session"),
        weeklyWindow: UsageWindow(remainingPercent: 40, resetAt: nil, label: "Weekly"),
        isAvailable: true,
        isStale: true,
        statusNote: "local .codex sessions"
    )
    let store = UsageQuotaStore(
        defaults: defaults,
        providers: [PreviewUsageQuotaProvider(snapshot: snapshot)]
    )
    store.showAIUsageQuotas = true

    return UsageQuotaStripView()
        .environmentObject(store)
        .padding()
        .frame(width: 380)
}

private struct PreviewUsageQuotaProvider: UsageQuotaProviding {
    let id: UsageProviderID = .codex
    let snapshot: UsageQuotaSnapshot

    func fetchSnapshot() async -> UsageQuotaSnapshot {
        snapshot
    }
}
