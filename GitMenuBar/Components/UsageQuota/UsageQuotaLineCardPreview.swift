import SwiftUI

// MARK: - Previews

private enum UsageQuotaLineCardPreviewFixtures {
    static let sessionDuration = 5 * 3600
    static let weeklyDuration = 7 * 86400
    static let monthlyDuration = 30 * 86400
    static let thresholds = UsageQuotaPace.defaultWarningThresholds

    /// Reset placed so the expected pace lands on the reference numbers:
    /// elapsed 46% (76/54 reserve), 36% (22/64 deficit), 13% (67/87 monthly).
    static func window(
        remainingPercent: Int,
        durationSeconds: Int,
        elapsed: Double,
        label: String
    ) -> UsageWindow {
        UsageWindow(
            remainingPercent: remainingPercent,
            resetAt: Date().addingTimeInterval(TimeInterval(durationSeconds) * (1 - elapsed)),
            label: label,
            durationSeconds: durationSeconds
        )
    }

    static let claudeWindow = UsageWindow(
        remainingPercent: 42,
        resetAt: nil,
        label: "Credits"
    )

    static let claudeRows: [UsageQuotaLineCard.RowData] = [
        UsageQuotaLineCard.RowData(
            title: "5-hour",
            window: window(remainingPercent: 76, durationSeconds: sessionDuration, elapsed: 0.46, label: "5h"),
            thresholds: thresholds,
            kind: .session
        ),
        UsageQuotaLineCard.RowData(
            title: "Weekly",
            window: window(remainingPercent: 22, durationSeconds: weeklyDuration, elapsed: 0.36, label: "7d"),
            thresholds: thresholds,
            kind: .weekly
        ),
        UsageQuotaLineCard.RowData(
            title: "Opus",
            window: window(remainingPercent: 76, durationSeconds: weeklyDuration, elapsed: 0.36, label: "Opus"),
            thresholds: thresholds,
            kind: .model
        ),
        UsageQuotaLineCard.RowData(
            title: "30-day",
            window: window(remainingPercent: 67, durationSeconds: monthlyDuration, elapsed: 0.13, label: "30-day"),
            thresholds: thresholds,
            kind: .model
        ),
        UsageQuotaLineCard.RowData(
            title: "Credits",
            window: claudeWindow,
            thresholds: thresholds,
            kind: .model
        )
    ]

    static let exhaustedRows: [UsageQuotaLineCard.RowData] = [
        UsageQuotaLineCard.RowData(
            title: "Weekly",
            window: window(remainingPercent: 0, durationSeconds: weeklyDuration, elapsed: 0.61, label: "7d"),
            thresholds: thresholds,
            kind: .weekly
        )
    ]

    static let staleSnapshot = UsageQuotaSnapshot(
        providerID: .cursor,
        displayName: "Cursor",
        sessionWindow: window(remainingPercent: 41, durationSeconds: 30 * 86400, elapsed: 0.35, label: "Plan"),
        weeklyWindow: nil,
        isAvailable: true,
        isStale: true,
        statusNote: "cursor usage-summary api"
    )

    static let costEstimates = UsageQuotaCostEstimate(rows: [
        UsageQuotaCostEstimate.Row(
            providerID: .codex,
            title: "OpenAI API",
            monthLabel: "Nov",
            amountUSD: 12.40
        ),
        UsageQuotaCostEstimate.Row(
            providerID: .claudeCode,
            title: "Anthropic API",
            monthLabel: "Nov",
            amountUSD: 28.60
        )
    ])
}

#Preview("Usage Quota Line Cards – Remaining") {
    lineCardPreviewColumns(showUsed: false)
}

#Preview("Usage Quota Line Cards – Used") {
    lineCardPreviewColumns(showUsed: true)
}

#Preview("Usage Quota Line Cards – Pace Hidden") {
    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
        UsageQuotaLineCard(
            providerID: .claudeCode,
            displayName: "Claude Code",
            pillText: nil,
            staleStyle: .none,
            rows: UsageQuotaLineCardPreviewFixtures.claudeRows,
            footnote: nil,
            showUsed: false,
            showsPace: false,
            workdaysPerWeek: 5,
            showsWorkdayTicks: true
        )
    }
    .padding()
    .frame(width: 320)
}

#Preview("Usage Quota Line Cards – Outdated and Exhausted") {
    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
        UsageQuotaLineCard(
            providerID: .antigravity,
            displayName: "Antigravity",
            pillText: nil,
            staleStyle: .text,
            rows: UsageQuotaLineCardPreviewFixtures.exhaustedRows,
            footnote: nil,
            showUsed: false,
            showsPace: true,
            workdaysPerWeek: 5,
            showsWorkdayTicks: true
        )
        UsageQuotaLineCard(
            providerID: .cursor,
            displayName: "Cursor",
            pillText: UsageQuotaLineCard.pillText(plan: "Pro", resetCredits: nil),
            staleStyle: .button(UsageQuotaLineCardPreviewFixtures.staleSnapshot),
            rows: UsageQuotaLineCardPreviewFixtures.claudeRows.prefix(1).map(\.self),
            footnote: nil,
            showUsed: true,
            showsPace: true,
            workdaysPerWeek: 5,
            showsWorkdayTicks: false
        )
    }
    .environment(MainMenuPresentationModel())
    .padding()
    .frame(width: 340)
}

#Preview("Usage Quota Line Cards – Long Names") {
    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
        UsageQuotaLineCard(
            providerID: .opencodeGo,
            displayName: "OpenCode Go",
            pillText: UsageQuotaLineCard.pillText(plan: "Business Team Annual", resetCredits: 12),
            staleStyle: .none,
            rows: [
                UsageQuotaLineCard.RowData(
                    title: "Sonnet 4.5 thinking",
                    window: UsageQuotaLineCardPreviewFixtures.window(
                        remainingPercent: 22,
                        durationSeconds: 7 * 86400,
                        elapsed: 0.36,
                        label: "Sonnet 4.5 thinking"
                    ),
                    thresholds: UsageQuotaLineCardPreviewFixtures.thresholds,
                    kind: .model
                )
            ],
            footnote: "12.50 credits",
            showUsed: false,
            showsPace: true,
            workdaysPerWeek: 5,
            showsWorkdayTicks: true
        )
    }
    .padding()
    .frame(width: 320)
}

#Preview("Usage Quota Cost Card") {
    UsageQuotaCostCard(estimates: UsageQuotaLineCardPreviewFixtures.costEstimates)
        .padding(WorkbenchMetrics.compactSpacing)
        .background(
            RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .padding()
        .frame(width: 340)
}

private func lineCardPreviewColumns(showUsed: Bool) -> some View {
    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
        UsageQuotaLineCard(
            providerID: .claudeCode,
            displayName: "Claude Code",
            pillText: nil,
            staleStyle: .none,
            rows: UsageQuotaLineCardPreviewFixtures.claudeRows,
            footnote: nil,
            showUsed: showUsed,
            showsPace: true,
            workdaysPerWeek: 5,
            showsWorkdayTicks: true
        )
        UsageQuotaLineCard(
            providerID: .openrouter,
            displayName: "OpenRouter",
            pillText: nil,
            staleStyle: .none,
            rows: [
                UsageQuotaLineCard.RowData(
                    title: "Credits",
                    window: UsageQuotaLineCardPreviewFixtures.claudeWindow,
                    thresholds: UsageQuotaLineCardPreviewFixtures.thresholds,
                    kind: .model
                )
            ],
            footnote: "$12.50 left",
            showUsed: showUsed,
            showsPace: true,
            workdaysPerWeek: 5,
            showsWorkdayTicks: true
        )
        UsageQuotaCostCard(estimates: UsageQuotaLineCardPreviewFixtures.costEstimates)
    }
    .padding(WorkbenchMetrics.compactSpacing)
    .frame(width: 340)
}
