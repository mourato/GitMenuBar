import SwiftUI

/// Mockup-style quota card shared by the menu submenu and the strip popover:
/// header (icon + name + plan pill) plus one segmented-dots row per limit window.
struct UsageQuotaDotsCard: View {
    struct RowData: Hashable {
        let title: String
        /// Compact reset countdown (e.g. `3h 30m`), nil when the reset is unknown.
        let countdown: String?
        let remainingPercent: Int
    }

    enum StaleStyle {
        case none
        case text
        case button(UsageQuotaSnapshot)
    }

    let providerID: UsageProviderID
    let displayName: String
    /// Plan pill (e.g. `Pro`, `Pro · 3 resets`); nil hides the pill.
    let pillText: String?
    let staleStyle: StaleStyle
    let rows: [RowData]
    /// Small secondary line under the header (e.g. OpenRouter credit balance).
    let footnote: String?
    /// When true the hero metric reads `N% used` instead of `N% left`.
    let showUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProviderIconView(providerID: providerID)
                    .frame(width: 15, height: 15)

                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))

                if let pillText {
                    Text(pillText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .accessibilityHidden(true)
                }

                switch staleStyle {
                case .none:
                    EmptyView()
                case .text:
                    Text("Outdated")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                case let .button(snapshot):
                    StaleQuotaInfoButton(snapshot: snapshot)
                }

                Spacer(minLength: 8)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                UsageQuotaDotsRow(row: row, showUsed: showUsed)
            }
        }
    }

    /// Compact reset countdown (e.g. `3h 30m`), nil when the reset is unknown or past.
    static func bareCountdown(until resetAt: Date?, now: Date = Date()) -> String? {
        guard let resetAt, resetAt > now else { return nil }
        let text = UsageQuotaFormatting.resetCountdown(until: resetAt, now: now)
        return text == "—" ? nil : text
    }

    /// Plan pill text: plan name (or interval fallback) plus reset-credit count.
    static func pillText(plan: String?, intervalChip: String?, resetCredits: Int?) -> String? {
        let base = plan ?? intervalChip
        guard let credits = resetCredits, credits > 0 else {
            return base
        }
        let creditsText = credits == 1 ? "1 reset" : "\(credits) resets"
        guard let base else {
            return creditsText
        }
        return "\(base) · \(creditsText)"
    }

    /// Dots filled for a 0–100 displayed percent on a 5-segment meter.
    static func filledSegments(displayPercent: Int) -> Int {
        guard displayPercent > 0 else { return 0 }
        return max(1, min(5, Int((Double(displayPercent) / 20).rounded())))
    }
}

private struct UsageQuotaDotsRow: View {
    let row: UsageQuotaDotsCard.RowData
    let showUsed: Bool

    var body: some View {
        HStack(spacing: 6) {
            (Text(row.title)
                .font(.system(size: 13, weight: .semibold))
                + Text(countdownSuffix)
                .font(.system(size: 13))
                .foregroundStyle(.secondary))
                .lineLimit(1)
                .frame(minWidth: 96, alignment: .leading)

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                ForEach(0 ..< 5, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index < filled ? tint : Color.primary.opacity(0.15))
                        .frame(width: 12, height: 7)
                }
            }
            .accessibilityHidden(true)

            Spacer(minLength: 6)

            (Text(percentNumber)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(percentColor)
                + Text(" \(percentSuffix)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title) \(displayPercent) percent \(percentSuffix)")
    }

    private var countdownSuffix: String {
        row.countdown.map { " \($0)" } ?? ""
    }

    private var displayPercent: Int {
        showUsed ? 100 - row.remainingPercent : row.remainingPercent
    }

    private var percentNumber: String {
        "\(displayPercent)%"
    }

    private var percentSuffix: String {
        showUsed ? "used" : "left"
    }

    private var filled: Int {
        UsageQuotaDotsCard.filledSegments(displayPercent: displayPercent)
    }

    private var tint: Color {
        UsageQuotaTrafficLightColor.swiftUI(for: row.remainingPercent)
    }

    private var percentColor: Color {
        row.remainingPercent < 15 ? .red : .primary
    }
}

/// Trailing estimate card: what current-month subscription tokens would cost via API.
struct UsageQuotaCostDotsCard: View {
    let estimates: UsageQuotaCostEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(estimates.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ProviderIconView(providerID: row.providerID)
                        .frame(width: 15, height: 15)

                    Text(row.title)
                        .font(.system(size: 14, weight: .semibold))

                    Text(row.monthLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .accessibilityHidden(true)

                    Spacer(minLength: 8)

                    (Text(UsageQuotaCostScanner.amountText(row.amountUSD))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(row.amountUSD == nil ? .secondary : .primary)
                        + Text(row.amountUSD == nil ? "" : " used")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title) \(row.monthLabel) \(costAccessibilityText(row.amountUSD))")
            }
        }
    }

    private func costAccessibilityText(_ amountUSD: Double?) -> String {
        guard let amountUSD else { return "amount unknown" }
        return String(format: "$%.2f used", amountUSD)
    }
}

#Preview("Usage Quota Dots Card") {
    VStack(spacing: 12) {
        UsageQuotaDotsCard(
            providerID: .codex,
            displayName: "Codex",
            pillText: UsageQuotaDotsCard.pillText(plan: "Pro", intervalChip: "5h", resetCredits: 3),
            staleStyle: .none,
            rows: [
                .init(title: "Session", countdown: "3h 30m", remainingPercent: 94),
                .init(title: "Weekly", countdown: "4d 22h", remainingPercent: 76)
            ],
            footnote: nil,
            showUsed: false
        )
        UsageQuotaDotsCard(
            providerID: .claudeCode,
            displayName: "Claude Code",
            pillText: UsageQuotaDotsCard.pillText(plan: nil, intervalChip: "7d", resetCredits: nil),
            staleStyle: .text,
            rows: [
                .init(title: "Weekly", countdown: "12h", remainingPercent: 8)
            ],
            footnote: nil,
            showUsed: false
        )
    }
    .padding()
    .frame(width: 340)
}
