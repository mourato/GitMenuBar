import SwiftUI

struct UsageQuotaSettingsSection: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore

    var body: some View {
        Toggle("Show AI usage in menu", isOn: $usageQuotaStore.showAIUsageQuotas)
            .toggleStyle(.switch)

        Toggle("Codex", isOn: $usageQuotaStore.showCodexUsageQuota)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        Toggle("Cursor", isOn: $usageQuotaStore.showCursorUsageQuota)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        Text(
            "Quota data stays on this Mac. GitMenuBar reads your local Codex and Cursor sessions "
                + "and calls unofficial usage endpoints only when refreshing — it never stores OAuth tokens."
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
            UsageQuotaSettingsSection()
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
