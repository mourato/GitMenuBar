import SwiftUI

struct UsageQuotaSettingsSection: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore
    @State private var openRouterAPIKey = ""

    private let apiKeyStore: any OpenRouterAPIKeyStoring

    init(apiKeyStore: any OpenRouterAPIKeyStoring = OpenRouterAPIKeyStore()) {
        self.apiKeyStore = apiKeyStore
    }

    var body: some View {
        Toggle("Show AI usage in menu", isOn: $usageQuotaStore.showAIUsageQuotas)
            .toggleStyle(.switch)

        Toggle("Codex", isOn: $usageQuotaStore.showCodexUsageQuota)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        Toggle("Cursor", isOn: $usageQuotaStore.showCursorUsageQuota)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        Toggle("OpenRouter", isOn: $usageQuotaStore.showOpenRouterUsageQuota)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        if usageQuotaStore.showOpenRouterUsageQuota {
            SecureField("OpenRouter API key", text: $openRouterAPIKey)
                .onAppear {
                    if openRouterAPIKey.isEmpty {
                        openRouterAPIKey = apiKeyStore.loadKey() ?? ""
                    }
                }
                .onChange(of: openRouterAPIKey) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        apiKeyStore.deleteKey()
                    } else {
                        apiKeyStore.saveKey(trimmed)
                    }
                }
        }

        Text(
            "Quota data stays on this Mac. GitMenuBar reads your local Codex and Cursor sessions "
                + "and calls provider usage endpoints only when refreshing — it never stores OAuth tokens. "
                + "Your OpenRouter API key is stored in your Keychain, never in GitMenuBar's preferences."
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
}

#Preview("Usage Quota Settings") {
    Form {
        Section {
            UsageQuotaSettingsSection(apiKeyStore: InMemoryOpenRouterAPIKeyStore())
        } header: {
            SettingsFormSectionHeader(
                title: "Usage Quotas",
                icon: "gauge.with.dots.needle.33percent"
            )
        }
    }
    .formStyle(.grouped)
    .environmentObject(UsageQuotaStore())
    .frame(width: 560, height: 280)
}
