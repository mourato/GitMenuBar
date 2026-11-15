import AppKit
import SwiftUI

struct UsageQuotaSummaryView: View {
    let snapshots: [UsageQuotaSnapshot]

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            ForEach(eligibleSnapshots) { snapshot in
                UsageQuotaSummaryItem(snapshot: snapshot)
            }
        }
    }

    private var eligibleSnapshots: [UsageQuotaSnapshot] {
        snapshots.compactMap { snapshot in
            guard snapshot.primaryDisplayWindow != nil || snapshot.tertiaryMonthlyWindow != nil || !snapshot.modelWindows.isEmpty else { return nil }
            return snapshot
        }.prefix(3).map(\.self)
    }
}

private struct UsageQuotaSummaryItem: View {
    let snapshot: UsageQuotaSnapshot

    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let resolved = UsageQuotaSummaryResolution.resolve(
            snapshot: snapshot,
            sessionThresholds: preferences.sessionWarningThresholds,
            weeklyThresholds: preferences.weeklyWarningThresholds
        ) {
            let showUsed = preferences.valueStyle == .used
            let reading = UsageQuotaPace.reading(
                for: resolved.window,
                showUsed: showUsed,
                thresholds: [],
                workdaysPerWeek: preferences.workdaysPerWeek,
                showPace: preferences.showsPace
            )
            let tint = resolved.alertLevel.color
            let description = UsageQuotaSummaryResolution.describe(
                displayName: snapshot.displayName,
                resolution: resolved,
                reading: reading,
                isStale: snapshot.isStale
            )
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                ProviderIconView(providerID: snapshot.providerID)
                if resolved.isExhausted {
                    LucideIconView(name: .circleAlert)
                        .foregroundStyle(UsageQuotaAlertLevel.error.color)
                    Text(UsageQuotaFormatting.compactDisplayValueText(
                        remainingPercent: resolved.window.remainingPercent,
                        kind: resolved.kind,
                        showUsed: showUsed
                    ))
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(UsageQuotaAlertLevel.error.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    switch preferences.meterStyle {
                    case .line:
                        UsageQuotaLineMeter(
                            fillPercent: reading.fillPercent,
                            tint: tint,
                            pacePercent: reading.pacePercent,
                            paceDeficit: reading.paceDeficit,
                            warningMarkerPercents: [],
                            workdayMarkerPercents: [],
                            compact: true
                        )
                        .frame(width: WorkbenchMetrics.quotaMeterCompactWidth)
                        percentText(resolved: resolved, showUsed: showUsed, tint: tint)
                    case .text:
                        percentText(resolved: resolved, showUsed: showUsed, tint: tint)
                    case .bars:
                        UsageQuotaSummaryBar(
                            fraction: Double(reading.fillPercent) / 100,
                            tint: tint,
                            track: WorkbenchPalette.neutralBorder(contrast: contrast)
                        )
                        percentText(resolved: resolved, showUsed: showUsed, tint: tint)
                    case .circular:
                        UsageQuotaCircularProgress(
                            fraction: Double(reading.fillPercent) / 100,
                            tint: tint
                        )
                        .frame(width: WorkbenchMetrics.quotaMeterWidth, height: WorkbenchMetrics.quotaMeterWidth)
                        percentText(resolved: resolved, showUsed: showUsed, tint: tint)
                    }
                }
            }
            .opacity(snapshot.isStale ? 0.72 : 1)
            .help(description)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(description)
        }
    }

    private func percentText(
        resolved: UsageQuotaSummaryResolution,
        showUsed: Bool,
        tint: Color
    ) -> some View {
        Text(UsageQuotaFormatting.compactDisplayValueText(
            remainingPercent: resolved.window.remainingPercent,
            kind: resolved.kind,
            showUsed: showUsed
        ))
        .font(WorkbenchTypography.captionStrong)
        .foregroundStyle(tint)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Compact fill bar for the summary's `.bars` meter style; sized by the quota meter metrics.
private struct UsageQuotaSummaryBar: View {
    let fraction: Double
    let tint: Color
    let track: Color

    var body: some View {
        Capsule(style: .continuous)
            .fill(track)
            .frame(width: WorkbenchMetrics.quotaMeterWidth, height: WorkbenchMetrics.quotaMeterHeight)
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: WorkbenchMetrics.quotaMeterWidth * CGFloat(fraction))
            }
    }
}

struct UsageQuotaCircularProgress: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.24), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1)
        .accessibilityHidden(true)
    }
}

struct ProviderIconView: View {
    let providerID: UsageProviderID
    var tint: Color?

    init(providerID: UsageProviderID, tint: Color? = nil) {
        self.providerID = providerID
        self.tint = tint
    }

    var body: some View {
        if let image = ProviderIconRenderer.image(for: providerID) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(tint ?? providerID.brandColor)
                .accessibilityHidden(true)
        } else {
            LucideIconView(name: fallbackIcon)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }

    private var fallbackIcon: LucideIconName {
        switch providerID {
        case .claudeCode:
            .cloud
        default:
            .sparkles
        }
    }
}

@MainActor
private enum ProviderIconRenderer {
    static func image(for providerID: UsageProviderID) -> NSImage? {
        let resourceName = switch providerID {
        case .claudeCode:
            "ProviderIcon-claude-code"
        case .codex:
            "ProviderIcon-codex"
        case .cursor:
            "ProviderIcon-cursor"
        case .openrouter:
            "ProviderIcon-openrouter"
        case .gemini:
            "ProviderIcon-gemini"
        case .antigravity:
            "ProviderIcon-antigravity"
        case .opencodeGo:
            "ProviderIcon-opencodego"
        }

        return SVGIconLoader.image(resourceName: resourceName)
    }
}

/// Shared quota severity tint for the summary and the cards; `normal` stays neutral.
extension UsageQuotaAlertLevel {
    var color: Color {
        switch self {
        case .normal:
            .secondary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

#Preview("Usage Quota Summary – Normal") {
    UsageQuotaSummaryPreviewHarness(snapshots: [
        previewSnapshot(.codex, name: "Codex", remainingPercent: 62),
        previewSnapshot(.cursor, name: "Cursor", remainingPercent: 70)
    ])
}

#Preview("Usage Quota Summary – Near Limit") {
    UsageQuotaSummaryPreviewHarness(snapshots: [
        previewSnapshot(.codex, name: "Codex", remainingPercent: 45),
        previewSnapshot(.cursor, name: "Cursor", remainingPercent: 12)
    ])
}

#Preview("Usage Quota Summary – Used") {
    UsageQuotaSummaryPreviewHarness(
        snapshots: [
            previewSnapshot(.codex, name: "Codex", remainingPercent: 62),
            previewSnapshot(.cursor, name: "Cursor", remainingPercent: 12)
        ],
        valueStyle: .used
    )
}

#Preview("Usage Quota Summary – Stale") {
    UsageQuotaSummaryPreviewHarness(snapshots: [
        previewSnapshot(.codex, name: "Codex", remainingPercent: 45, isStale: true)
    ])
}

#Preview("Usage Quota Summary – Bars") {
    UsageQuotaSummaryPreviewHarness(
        snapshots: [
            previewSnapshot(.codex, name: "Codex", remainingPercent: 45),
            previewSnapshot(.cursor, name: "Cursor", remainingPercent: 12)
        ],
        meterStyle: .bars
    )
}

#Preview("Usage Quota Summary – Circular") {
    UsageQuotaSummaryPreviewHarness(
        snapshots: [
            previewSnapshot(.codex, name: "Codex", remainingPercent: 45),
            previewSnapshot(.cursor, name: "Cursor", remainingPercent: 12)
        ],
        meterStyle: .circular
    )
}

#Preview("Usage Quota Summary – Weekly Exhausted") {
    UsageQuotaSummaryPreviewHarness(snapshots: [
        UsageQuotaSnapshot(
            providerID: .antigravity,
            displayName: "Antigravity",
            sessionWindow: nil,
            weeklyWindow: UsageWindow(
                remainingPercent: 0,
                resetAt: Date().addingTimeInterval(86400),
                label: "Weekly",
                durationSeconds: 7 * 86400
            ),
            isAvailable: true
        )
    ])
}

#Preview("Usage Quota Summary – Critical Weekly") {
    UsageQuotaSummaryPreviewHarness(snapshots: [
        UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            sessionWindow: UsageWindow(
                remainingPercent: 76,
                resetAt: Date().addingTimeInterval(3600),
                label: "5h",
                durationSeconds: 5 * 3600
            ),
            weeklyWindow: UsageWindow(
                remainingPercent: 22,
                resetAt: Date().addingTimeInterval(86400),
                label: "7d",
                durationSeconds: 7 * 86400
            ),
            isAvailable: true
        )
    ])
}

private func previewSnapshot(
    _ providerID: UsageProviderID,
    name: String,
    remainingPercent: Int,
    isStale: Bool = false
) -> UsageQuotaSnapshot {
    UsageQuotaSnapshot(
        providerID: providerID,
        displayName: name,
        sessionWindow: UsageWindow(
            remainingPercent: remainingPercent,
            resetAt: Date().addingTimeInterval(3600),
            label: "5h",
            durationSeconds: 5 * 3600
        ),
        weeklyWindow: nil,
        isAvailable: true,
        isStale: isStale
    )
}

private struct UsageQuotaSummaryPreviewHarness: View {
    let snapshots: [UsageQuotaSnapshot]
    @State private var preferences: UsageQuotaPresentationPreferences

    init(
        snapshots: [UsageQuotaSnapshot],
        valueStyle: UsageQuotaPresentationPreferences.ValueStyle = .left,
        meterStyle: UsageQuotaPresentationPreferences.MeterStyle = .text
    ) {
        self.snapshots = snapshots
        let name = "UsageQuotaSummaryPreview-\(valueStyle.rawValue)-\(meterStyle.rawValue)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let preferences = UsageQuotaPresentationPreferences(defaults: defaults)
        preferences.valueStyle = valueStyle
        preferences.meterStyle = meterStyle
        _preferences = State(wrappedValue: preferences)
    }

    var body: some View {
        UsageQuotaSummaryView(snapshots: snapshots)
            .environment(preferences)
            .padding()
    }
}
