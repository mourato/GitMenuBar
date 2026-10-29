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
            guard snapshot.primaryDisplayWindow != nil || !snapshot.modelWindows.isEmpty else { return nil }
            return snapshot
        }.prefix(3).map(\.self)
    }
}

private struct UsageQuotaSummaryItem: View {
    let snapshot: UsageQuotaSnapshot

    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let window = snapshot.primaryDisplayWindow ?? tightestModelWindow {
            let displayPercent = preferences.valueStyle == .left ? window.remainingPercent : 100 - window.remainingPercent
            let tint = UsageQuotaFormatting.alertLevel(
                remainingPercent: window.remainingPercent,
                thresholds: warningThresholds
            ).color
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                ProviderIconView(providerID: snapshot.providerID)

                switch preferences.meterStyle {
                case .text:
                    Text("\(displayPercent)%")
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundStyle(tint)
                case .bars:
                    UsageQuotaSummaryBar(
                        fraction: Double(displayPercent) / 100,
                        tint: tint,
                        track: WorkbenchPalette.neutralBorder(contrast: contrast)
                    )
                }
            }
            .opacity(snapshot.isStale ? 0.72 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(displayPercent: displayPercent))
        }
    }

    private var tightestModelWindow: UsageWindow? {
        snapshot.modelWindows.min { $0.remainingPercent < $1.remainingPercent }
    }

    /// The session thresholds apply when the session window drives the summary; otherwise weekly.
    private var warningThresholds: [Int] {
        snapshot.sessionWindow == nil ? preferences.weeklyWarningThresholds : preferences.sessionWarningThresholds
    }

    private func accessibilityLabel(displayPercent: Int) -> String {
        let suffix = preferences.valueStyle == .left ? "left" : "used"
        let staleText = snapshot.isStale ? ", stale" : ""
        return "\(snapshot.displayName), \(displayPercent) percent \(suffix)\(staleText)"
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
            Image(systemName: fallbackSymbol)
                .font(WorkbenchTypography.captionStrong)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }

    private var fallbackSymbol: String {
        switch providerID {
        case .claudeCode:
            "cloud.fill"
        default:
            "sparkles"
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
