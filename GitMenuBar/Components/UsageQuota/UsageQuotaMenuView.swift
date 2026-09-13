import AppKit
import SwiftUI

struct UsageQuotaMenuView: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore
    @EnvironmentObject private var preferences: UsageQuotaPresentationPreferences

    static let width: CGFloat = 320

    var body: some View {
        let snapshots = orderedSnapshots
        VStack(alignment: .leading, spacing: 12) {
            if snapshots.isEmpty {
                Text("No usage figures available")
                    .font(UsageQuotaMenuTypography.supporting)
                    .foregroundStyle(UsageQuotaMenuInk.secondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(snapshots) { snapshot in
                    providerSection(snapshot)
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
        let metrics = UsageQuotaPresentationPreferences.Metric.allCases.compactMap { metric in
            UsageQuotaMenuPresentation.value(for: metric, snapshot: snapshot, valueStyle: preferences.valueStyle)
                .map { (metric, $0) }
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ProviderIconView(providerID: snapshot.providerID)
                    .frame(width: 15, height: 15)
                Text(snapshot.displayName)
                    .font(UsageQuotaMenuTypography.header)
                    .foregroundStyle(UsageQuotaMenuInk.primary)
                if snapshot.isStale {
                    Text("Outdated")
                        .font(UsageQuotaMenuTypography.plan)
                        .foregroundStyle(UsageQuotaMenuInk.tertiary)
                }
                Spacer(minLength: 8)
            }
            .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, entry in
                    UsageQuotaMenuMetricRow(
                        metric: entry.0,
                        value: entry.1,
                        snapshot: snapshot,
                        isCondensed: index > 0
                    )
                }
            }
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(UsageQuotaMenuInk.card)
            )
        }
        .opacity(snapshot.isStale ? 0.72 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(snapshot.displayName)
    }
}

struct UsageQuotaMenuBarGroup: Equatable, Identifiable {
    let providerID: UsageProviderID
    let values: [String]
    let fractions: [Double]

    var id: UsageProviderID {
        providerID
    }
}

enum UsageQuotaMenuPresentation {
    @MainActor
    static func groups(
        snapshots: [UsageQuotaSnapshot],
        preferences: UsageQuotaPresentationPreferences
    ) -> [UsageQuotaMenuBarGroup] {
        let snapshotsByProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.providerID, $0) })
        return preferences.orderedProviderIDs.compactMap { providerID in
            guard let snapshot = snapshotsByProvider[providerID] else { return nil }
            var values: [String] = []
            var fractions: [Double] = []
            for metric in preferences.selectedMetrics(for: providerID) {
                guard let reading = value(for: metric, snapshot: snapshot, valueStyle: preferences.valueStyle) else { continue }
                values.append(reading.compactValue)
                if let fraction = reading.fraction {
                    fractions.append(fraction)
                }
            }
            return values.isEmpty ? nil : UsageQuotaMenuBarGroup(providerID: providerID, values: values, fractions: fractions)
        }
    }

    static func value(
        for metric: UsageQuotaPresentationPreferences.Metric,
        snapshot: UsageQuotaSnapshot,
        valueStyle: UsageQuotaPresentationPreferences.ValueStyle
    ) -> UsageQuotaMenuReading? {
        switch metric {
        case .session:
            guard let window = snapshot.sessionWindow else { return nil }
            return reading(for: window, valueStyle: valueStyle)
        case .weekly:
            guard let window = snapshot.weeklyWindow else { return nil }
            return reading(for: window, valueStyle: valueStyle)
        case .credits:
            if let resetCreditsAvailable = snapshot.resetCreditsAvailable {
                let label = resetCreditsAvailable == 1 ? "1 reset" : "\(resetCreditsAvailable) resets"
                return UsageQuotaMenuReading(label: "Credits", value: label, compactValue: label, fraction: nil)
            }
            guard let creditValueText = snapshot.creditValueText else { return nil }
            return UsageQuotaMenuReading(label: "Credits", value: creditValueText, compactValue: creditValueText, fraction: nil)
        }
    }

    private static func reading(
        for window: UsageWindow,
        valueStyle: UsageQuotaPresentationPreferences.ValueStyle
    ) -> UsageQuotaMenuReading {
        let percent = valueStyle == .left ? window.remainingPercent : 100 - window.remainingPercent
        let suffix = valueStyle == .left ? "left" : "used"
        let fraction = Double(percent) / 100
        return UsageQuotaMenuReading(
            label: window.label,
            value: "\(percent)% \(suffix)",
            compactValue: "\(percent)%",
            fraction: fraction
        )
    }
}

struct UsageQuotaMenuReading {
    let label: String
    let value: String
    let compactValue: String
    let fraction: Double?
}

private struct UsageQuotaMenuMetricRow: View {
    let metric: UsageQuotaPresentationPreferences.Metric
    let value: UsageQuotaMenuReading
    let snapshot: UsageQuotaSnapshot
    let isCondensed: Bool

    var body: some View {
        if let window {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(value.label)
                        .font(UsageQuotaMenuTypography.label)
                        .foregroundStyle(UsageQuotaMenuInk.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(value.value)
                        .font(UsageQuotaMenuTypography.supporting)
                        .foregroundStyle(UsageQuotaMenuInk.secondary)
                        .monospacedDigit()
                }
                UsageQuotaMenuMeter(
                    fillPercent: Int((value.fraction ?? 0) * 100),
                    remainingPercent: window.remainingPercent
                )
                HStack(spacing: 8) {
                    Text(UsageQuotaFormatting.resetCountdown(until: window.resetAt))
                    Spacer(minLength: 8)
                    Text(UsageQuotaFormatting.resetClockTime(until: window.resetAt))
                }
                .font(UsageQuotaMenuTypography.supporting)
                .foregroundStyle(UsageQuotaMenuInk.secondary)
                .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(snapshot.displayName) \(value.label), \(value.value)")
        } else {
            HStack(spacing: 10) {
                Text(value.label)
                    .font(UsageQuotaMenuTypography.label)
                    .foregroundStyle(UsageQuotaMenuInk.primary)
                Spacer(minLength: 12)
                Text(value.value)
                    .font(UsageQuotaMenuTypography.supporting)
                    .foregroundStyle(UsageQuotaMenuInk.primary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.top, isCondensed ? 2 : 6)
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var window: UsageWindow? {
        switch metric {
        case .session:
            snapshot.sessionWindow
        case .weekly:
            snapshot.weeklyWindow
        case .credits:
            nil
        }
    }
}

private struct UsageQuotaMenuMeter: View {
    let fillPercent: Int
    let remainingPercent: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(UsageQuotaMenuInk.track)
                Capsule()
                    .fill(usageQuotaMenuColor(for: remainingPercent))
                    .frame(width: min(proxy.size.width, max(5, proxy.size.width * CGFloat(fillPercent) / 100)))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

struct UsageQuotaMenuBarStrip: View {
    let groups: [UsageQuotaMenuBarGroup]
    let style: UsageQuotaPresentationPreferences.MeterStyle

    var body: some View {
        switch style {
        case .text:
            HStack(spacing: 11) {
                ForEach(groups) { group in
                    HStack(spacing: 4) {
                        ProviderIconView(providerID: group.providerID)
                            .frame(width: 16, height: 16)
                        if group.values.count == 1 {
                            Text(group.values[0])
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            VStack(alignment: .trailing, spacing: -2) {
                                ForEach(Array(group.values.prefix(2).enumerated()), id: \.offset) { _, value in
                                    Text(value)
                                }
                            }
                            .font(.system(size: 9, weight: .semibold))
                        }
                    }
                }
            }
            .foregroundStyle(.black)
            .monospacedDigit()
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .fixedSize()
        case .bars:
            Canvas { context, size in
                let fractions = groups.flatMap(\.fractions).prefix(4)
                let count = max(1, fractions.count)
                let pad = max(1, (size.width * 0.08).rounded())
                let gap = max(1, (size.width * 0.03).rounded())
                let trackWidth = size.width - 2 * pad
                let slots = CGFloat(max(2, count))
                let trackHeight = max(1, ((size.height - 2 * pad - (slots - 1) * gap) / slots).rounded(.down))
                let total = CGFloat(count) * trackHeight + CGFloat(count - 1) * gap
                let top = pad + ((size.height - 2 * pad - total) / 2).rounded(.down)
                let radius = max(1, (trackHeight / 3).rounded(.down))

                for (index, fraction) in fractions.enumerated() {
                    let barOriginY = top + CGFloat(index) * (trackHeight + gap)
                    let track = CGRect(x: pad, y: barOriginY, width: trackWidth, height: trackHeight)
                    context.fill(Path(roundedRect: track, cornerRadius: radius), with: .color(.black.opacity(0.24)))
                    let filled = max(1, trackWidth * CGFloat(min(max(fraction, 0), 1)))
                    let fill = CGRect(x: pad, y: barOriginY, width: filled, height: trackHeight)
                    context.fill(Path(roundedRect: fill, cornerRadius: radius), with: .color(.black))
                }
            }
            .frame(width: 18, height: 18)
        }
    }
}

private enum UsageQuotaMenuTypography {
    static let label = Font(NSFont.menuFont(ofSize: 0)).weight(.semibold)
    static let supporting = Font(NSFont.menuFont(ofSize: max(10, NSFont.menuFont(ofSize: 0).pointSize - 1)))
    static let header = Font(NSFont.menuFont(ofSize: 0)).weight(.semibold)
    static let plan = Font(NSFont.menuFont(ofSize: max(9, NSFont.menuFont(ofSize: 0).pointSize - 2)))
}

private enum UsageQuotaMenuInk {
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let track = Color(nsColor: .tertiaryLabelColor)
    static let card = Color(nsColor: .quaternarySystemFill)
}

private func usageQuotaMenuColor(for remainingPercent: Int) -> Color {
    switch UsageQuotaFormatting.trafficLightColor(for: remainingPercent) {
    case .green:
        Color(nsColor: .systemGreen)
    case .amber:
        Color(nsColor: .systemYellow)
    case .red:
        Color(nsColor: .systemRed)
    }
}

#Preview("Usage Quota Menu") {
    UsageQuotaMenuPreviewHarness()
}

private struct UsageQuotaMenuPreviewHarness: View {
    @StateObject private var store: UsageQuotaStore
    @StateObject private var preferences: UsageQuotaPresentationPreferences

    init() {
        let snapshot = UsageQuotaSnapshot(
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
        let store = UsageQuotaStore(providers: [UsageQuotaPreviewProvider(snapshot: snapshot)])
        store.showAIUsageQuotas = true
        _store = StateObject(wrappedValue: store)
        _preferences = StateObject(wrappedValue: UsageQuotaPresentationPreferences())
    }

    var body: some View {
        UsageQuotaMenuView()
            .environmentObject(store)
            .environmentObject(preferences)
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
