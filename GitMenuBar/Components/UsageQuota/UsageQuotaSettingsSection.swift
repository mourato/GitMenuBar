import SwiftUI

struct UsageQuotaSettingsSection: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore

    var body: some View {
        Toggle("Show AI usage in menu", isOn: $usageQuotaStore.showAIUsageQuotas)
            .toggleStyle(.switch)

        providerToggle("Codex", providerID: .codex, isOn: $usageQuotaStore.showCodexUsageQuota)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        providerToggle("Cursor", providerID: .cursor, isOn: $usageQuotaStore.showCursorUsageQuota)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        providerToggle("OpenRouter", providerID: .openrouter, isOn: $usageQuotaStore.showOpenRouterUsageQuota)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        Text(
            "Quota data stays on this Mac. GitMenuBar reads your local Codex and Cursor sessions "
                + "and calls provider usage endpoints only when refreshing — it never stores OAuth tokens. "
                + "OpenRouter quota uses the OpenRouter provider credential configured in AI settings."
        )
        .font(WorkbenchTypography.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        Button("Refresh now") {
            usageQuotaStore.refresh(reason: .manual)
        }
        .buttonStyle(.borderless)
        .font(WorkbenchTypography.detail)
        .disabled(!usageQuotaStore.showAIUsageQuotas)
    }

    private func providerToggle(
        _ title: String,
        providerID: UsageProviderID,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                ProviderIconView(providerID: providerID)
                Text(title)
            }
        }
    }
}

#Preview("Usage Quota Settings") {
    let credentialStore = InMemoryAIAPIKeyStore()
    let providers: [any UsageQuotaProviding] = [
        CodexUsageProvider(),
        CursorUsageProvider(),
        OpenRouterUsageProvider(keyStore: credentialStore)
    ]

    Form {
        Section {
            UsageQuotaSettingsSection()
        } header: {
            SettingsFormSectionHeader(
                title: "Quotas",
                icon: "gauge.with.dots.needle.33percent"
            )
        }
    }
    .formStyle(.grouped)
    .environmentObject(UsageQuotaStore(providers: providers))
    .frame(width: 560, height: 280)
}
