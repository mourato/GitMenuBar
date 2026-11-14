import SwiftUI

/// Quota card shared by the menu submenu and the strip popover: header
/// (icon + name + optional plan/reset chip) plus one continuous Line row per
/// limit window. Both surfaces always use this card; the compact meter style
/// preference only changes the status-item strip.
struct UsageQuotaLineCard: View {
    struct RowData {
        let title: String
        let window: UsageWindow
        /// Consumed-percent warning thresholds for this row's window (session or weekly).
        let thresholds: [Int]
        let kind: UsageQuotaWindowKind

        var isExhausted: Bool {
            UsageQuotaFormatting.isWeeklyExhausted(
                remainingPercent: window.remainingPercent,
                kind: kind
            )
        }

        var alertLevel: UsageQuotaAlertLevel {
            if isExhausted {
                return .error
            }
            return UsageQuotaFormatting.alertLevel(
                remainingPercent: window.remainingPercent,
                thresholds: thresholds
            )
        }

        /// Display reading from the pace owner; the card never computes pace itself.
        func reading(
            showUsed: Bool,
            showsPace: Bool,
            workdaysPerWeek: Int,
            now: Date
        ) -> UsageQuotaPace.Reading {
            UsageQuotaPace.reading(
                for: window,
                showUsed: showUsed,
                thresholds: thresholds,
                workdaysPerWeek: workdaysPerWeek,
                showPace: showsPace,
                now: now
            )
        }
    }

    enum StaleStyle {
        case none
        case text
        case button(UsageQuotaSnapshot)
    }

    let providerID: UsageProviderID
    let displayName: String
    /// Plan and reset-credit chip (e.g. `Pro · 3 resets`); nil hides the chip.
    let pillText: String?
    let staleStyle: StaleStyle
    let rows: [RowData]
    /// Small secondary line under the header (e.g. OpenRouter credit balance).
    let footnote: String?
    /// When true rows read used percentages instead of remaining.
    let showUsed: Bool
    let showsPace: Bool
    let workdaysPerWeek: Int
    let showsWorkdayTicks: Bool

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            header

            if let footnote {
                Text(footnote)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if !rows.isEmpty {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: WorkbenchMetrics.compactSpacing,
                    verticalSpacing: WorkbenchMetrics.chipSpacing
                ) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        let reading = row.reading(
                            showUsed: showUsed,
                            showsPace: showsPace,
                            workdaysPerWeek: workdaysPerWeek,
                            now: now
                        )
                        GridRow(alignment: .center) {
                            rowLabel(row: row, reading: reading)

                            UsageQuotaLineMeter(
                                fillPercent: reading.fillPercent,
                                tint: row.alertLevel.color,
                                pacePercent: reading.pacePercent,
                                paceDeficit: reading.paceDeficit,
                                warningMarkerPercents: reading.warningMarkerPercents,
                                workdayMarkerPercents: showsWorkdayTicks ? reading.workdayMarkerPercents : []
                            )
                            .frame(minWidth: 44)

                            Text(valueText(for: row))
                                .font(WorkbenchTypography.detail.weight(.semibold))
                                .foregroundStyle(percentColor(for: row))
                                .monospacedDigit()
                                .lineLimit(1)
                                .frame(minWidth: 32, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(displayName), \(row.title)")
                        .accessibilityValue(Self.rowAccessibilityValue(reading: reading, isExhausted: row.isExhausted))
                        .help(Self.rowAccessibilityValue(reading: reading, isExhausted: row.isExhausted))
                    }
                }
            }
        }
    }

    /// One icon, one name, at most one plan/reset chip, and the stale marker.
    /// The name keeps its width; the chip wraps before the name loses legibility.
    private var header: some View {
        HStack(alignment: .center, spacing: WorkbenchMetrics.chipSpacing) {
            ProviderIconView(providerID: providerID)
                .frame(width: 15, height: 15)

            Text(displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(2)
                .accessibilityHidden(true)

            if let pillText {
                Text(pillText)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .layoutPriority(1)
                    .accessibilityHidden(true)
            }

            switch staleStyle {
            case .none:
                EmptyView()
            case .text:
                Text("Outdated")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityHidden(true)
            case let .button(snapshot):
                StaleQuotaInfoButton(snapshot: snapshot)
                    .layoutPriority(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: hasStaleInfoButton ? .contain : .ignore)
        .accessibilityLabel(
            Self.headerAccessibilityText(
                displayName: displayName,
                pillText: pillText,
                isStale: isStale
            )
        )
    }

    /// Window title plus the compact reset countdown; the tooltip and
    /// VoiceOver keep the full "Resets in …" sentence.
    private func rowLabel(row: RowData, reading: UsageQuotaPace.Reading) -> some View {
        HStack(spacing: WorkbenchMetrics.microSpacing) {
            Text(row.title)
                .font(WorkbenchTypography.detail)
                .lineLimit(1)

            if let countdown = reading.resetCountdownText {
                Text("↻ \(countdown)")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    private func valueText(for row: RowData) -> String {
        UsageQuotaFormatting.compactDisplayValueText(
            remainingPercent: row.window.remainingPercent,
            kind: row.kind,
            showUsed: showUsed
        )
    }

    private func percentColor(for row: RowData) -> Color {
        row.alertLevel == .normal ? .primary : row.alertLevel.color
    }

    private var hasStaleInfoButton: Bool {
        if case .button = staleStyle {
            return true
        }
        return false
    }

    private var isStale: Bool {
        if case .none = staleStyle {
            return false
        }
        return true
    }

    /// VoiceOver hears provider, plan, resets, and stale state once, instead of
    /// relying on the visually hidden chip.
    static func headerAccessibilityText(displayName: String, pillText: String?, isStale: Bool) -> String {
        var parts = [displayName]
        if let pillText {
            parts.append(pillText.replacingOccurrences(of: " · ", with: ", "))
        }
        if isStale {
            parts.append("Outdated")
        }
        return parts.joined(separator: ", ")
    }

    /// Row reading order: percentage direction, reset, then the pace captions.
    static func rowAccessibilityValue(reading: UsageQuotaPace.Reading, isExhausted: Bool) -> String {
        var parts = [isExhausted ? "quota exhausted" : reading.percentText]
        for text in [reading.resetText, reading.paceLeftText, reading.paceRightText] {
            if let text {
                parts.append(text)
            }
        }
        return parts.joined(separator: ", ")
    }

    /// Header chip: plan and redeemable resets only. The interval already lives
    /// in the row title, so it is not repeated here.
    static func pillText(plan: String?, resetCredits: Int?) -> String? {
        guard let credits = resetCredits, credits > 0 else {
            return plan
        }
        let creditsText = credits == 1 ? "1 reset" : "\(credits) resets"
        guard let plan else {
            return creditsText
        }
        return "\(plan) · \(creditsText)"
    }
}

/// One legend per visible surface: rows show only `%`, so the percentage
/// direction is stated once here and each row's VoiceOver value keeps it.
struct UsageQuotaValueStyleCaption: View {
    let showUsed: Bool

    var body: some View {
        Text(showUsed ? "% used" : "% remaining")
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

/// Trailing estimate card: what current-month subscription tokens would cost via API.
struct UsageQuotaCostCard: View {
    let estimates: UsageQuotaCostEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                Text("API spend")
                    .font(WorkbenchTypography.sectionLabel)
                    .foregroundStyle(.primary)

                if let periodLabel {
                    Text(periodLabel)
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headerAccessibilityText)

            ForEach(Array(estimates.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: WorkbenchMetrics.chipSpacing) {
                    ProviderIconView(providerID: row.providerID)
                        .frame(width: 15, height: 15)

                    Text(row.title)
                        .font(WorkbenchTypography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: WorkbenchMetrics.compactSpacing)

                    Text(UsageQuotaCostScanner.amountText(row.amountUSD))
                        .font(WorkbenchTypography.body.weight(.semibold))
                        .foregroundStyle(row.amountUSD == nil ? .secondary : .primary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title), \(costAccessibilityText(row.amountUSD))")
            }
        }
    }

    /// The month is stated once for the card instead of once per provider row.
    private var periodLabel: String? {
        estimates.rows.first?.monthLabel
    }

    private var headerAccessibilityText: String {
        guard let periodLabel else { return "API spend" }
        return "API spend, \(periodLabel)"
    }

    private func costAccessibilityText(_ amountUSD: Double?) -> String {
        guard let amountUSD else { return "amount unknown" }
        return String(format: "$%.2f", amountUSD)
    }
}
