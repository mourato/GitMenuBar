import SwiftUI

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

#Preview("Usage Quota Strip – Collapsed Multi Provider") {
    UsageQuotaStripPreviewHarness(snapshots: PreviewUsageQuotaSnapshotFactory.multiProvider)
}

#Preview("Usage Quota Strip – Popover Multi Provider") {
    UsageQuotaStripPreviewHarness(snapshots: PreviewUsageQuotaSnapshotFactory.multiProvider)
}

#Preview("Usage Quota Strip – No Eligible Snapshot") {
    UsageQuotaStripPreviewHarness(snapshots: [])
}

#Preview("Usage Quota Strip – Claude Models") {
    UsageQuotaStripPreviewHarness(
        snapshots: [PreviewUsageQuotaSnapshotFactory.claudeCode()]
    )
}

private struct UsageQuotaStripPreviewHarness: View {
    let snapshots: [UsageQuotaSnapshot]

    var body: some View {
        if let defaults = UserDefaults(suiteName: previewDefaultsName) {
            UsageQuotaStripView()
                .environmentObject(previewStore(defaults: defaults))
                .environmentObject(MainMenuPresentationModel())
                .frame(width: 380)
        }
    }

    private func previewStore(defaults: UserDefaults) -> UsageQuotaStore {
        defaults.removePersistentDomain(forName: previewDefaultsName)
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

    static func claudeCode() -> UsageQuotaSnapshot {
        UsageQuotaSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            sessionWindow: UsageWindow(
                remainingPercent: 77,
                resetAt: Date().addingTimeInterval(8100),
                label: "5h",
                durationSeconds: 5 * 3600
            ),
            weeklyWindow: UsageWindow(
                remainingPercent: 58,
                resetAt: Date().addingTimeInterval(86400 * 3),
                label: "7d",
                durationSeconds: 7 * 86400
            ),
            modelWindows: [
                UsageWindow(
                    remainingPercent: 88,
                    resetAt: Date().addingTimeInterval(86400 * 3),
                    label: "Sonnet",
                    durationSeconds: 7 * 86400
                ),
                UsageWindow(
                    remainingPercent: 32,
                    resetAt: Date().addingTimeInterval(86400 * 3),
                    label: "Opus",
                    durationSeconds: 7 * 86400
                )
            ],
            isAvailable: true,
            statusNote: "Claude Code OAuth usage API"
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
