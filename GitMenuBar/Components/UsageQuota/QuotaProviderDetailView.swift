import SwiftUI

/// Expanded options for one quota provider, grouped under caption headers:
/// API key (key providers only), menu-bar figures, and strip position.
struct QuotaProviderDetailView: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let providerID: UsageProviderID
    var keyStore: any AIAPIKeyStore = AIKeychainStore() // justified: injectable Keychain seam (real store vs in-memory previews)

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            if providerID.quotaCredentialID != nil {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    blockCaption("API key")
                    QuotaAPIKeyEditorView(providerID: providerID, keyStore: keyStore)
                }
            }

            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                blockCaption("Menu bar")
                metricChips
            }
        }
        .padding(.top, WorkbenchMetrics.microSpacing)
    }

    private var metricChips: some View {
        HStack(spacing: WorkbenchMetrics.microSpacing) {
            ForEach(UsageQuotaPresentationPreferences.Metric.allCases) { metric in
                let selected = preferences.selectedMetrics(for: providerID).contains(metric)
                Button {
                    preferences.toggleMetric(metric, for: providerID)
                } label: {
                    HStack(spacing: WorkbenchMetrics.microSpacing) {
                        if selected {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                        Text(metric.title)
                    }
                    .font(WorkbenchTypography.caption)
                    .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                    .frame(minHeight: WorkbenchMetrics.minimumHitTarget)
                    .background(
                        selected
                            ? WorkbenchPalette.accentFill(contrast: colorSchemeContrast)
                            : WorkbenchPalette.hoverFill(),
                        in: Capsule()
                    )
                    .foregroundStyle(selected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(metric.title) figure")
                .accessibilityValue(selected ? "Shown" : "Hidden")
            }
        }
        .disabled(!usageQuotaStore.showAIUsageQuotas || !usageQuotaStore.isProviderEnabled(providerID))
    }

    private func blockCaption(_ text: String) -> Text {
        Text(text)
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview("Quota Provider Detail") {
        Form {
            QuotaProviderDetailView(providerID: .opencodeGo)
        }
        .formStyle(.grouped)
        .environment(UsageQuotaStore(providers: []))
        .environment(UsageQuotaPresentationPreferences())
        .frame(width: 560)
    }
#endif
