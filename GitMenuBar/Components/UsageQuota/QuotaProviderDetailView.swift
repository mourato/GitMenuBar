import SwiftUI

/// Expanded options for one quota provider: API key (key providers only)
/// and the two menu-bar metric menus. The first menu picks the primary
/// metric; the second picks an optional additional metric.
struct QuotaProviderDetailView: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences

    let providerID: UsageProviderID

    private var selectedMetrics: [UsageQuotaPresentationPreferences.Metric] {
        preferences.selectedMetrics(for: providerID)
    }

    private var primaryMetric: UsageQuotaPresentationPreferences.Metric {
        selectedMetrics.first ?? .session
    }

    private var secondaryMetric: UsageQuotaPresentationPreferences.Metric? {
        selectedMetrics.count > 1 ? selectedMetrics[1] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            if providerID.quotaCredentialID != nil {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    blockCaption("API key")
                    QuotaAPIKeyEditorView(providerID: providerID)
                }
            }

            Picker(
                "Menu bar shows",
                selection: Binding(
                    get: { primaryMetric },
                    set: { preferences.setPrimaryMetric($0, for: providerID) }
                )
            ) {
                ForEach(UsageQuotaPresentationPreferences.Metric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.menu)

            Picker(
                "Second metric",
                selection: Binding<UsageQuotaPresentationPreferences.Metric?>(
                    get: { secondaryMetric },
                    set: { preferences.setSecondaryMetric($0, for: providerID) }
                )
            ) {
                Text("None").tag(UsageQuotaPresentationPreferences.Metric?.none)
                ForEach(UsageQuotaPresentationPreferences.Metric.allCases.filter { $0 != primaryMetric }) { metric in
                    Text(metric.title).tag(UsageQuotaPresentationPreferences.Metric?.some(metric))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.bottom, WorkbenchMetrics.microSpacing)
        .disabled(!usageQuotaStore.isProviderEnabled(providerID))
    }

    private func blockCaption(_ text: String) -> Text {
        Text(text)
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview("Quota Provider Detail") {
        let keyStore = InMemoryAIAPIKeyStore(storage: [.opencodego: "test-key-1234"])
        let coordinator = AICommitCoordinator(
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            keychainStore: keyStore,
            messageService: AICommitMessageService(),
            gitManager: GitManager(repositoryPathOverride: "/tmp")
        )
        let preferences = UsageQuotaPresentationPreferences(keyStore: keyStore)
        preferences.refreshQuotaKeyPresence()

        return Form {
            QuotaProviderDetailView(providerID: .opencodeGo)
        }
        .formStyle(.grouped)
        .environment(UsageQuotaStore(providers: []))
        .environment(preferences)
        .environment(coordinator)
        .frame(width: 560)
    }
#endif
