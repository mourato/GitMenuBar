import SwiftUI

struct UsageQuotaSettingsSection: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                Text("AI Usage Quotas")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)

            Toggle(isOn: $usageQuotaStore.showAIUsageQuotas) {
                Text("Show AI usage in menu")
                    .font(WorkbenchTypography.body)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("Show AI usage in menu")

            Toggle(isOn: $usageQuotaStore.showCodexUsageQuota) {
                Text("Codex")
                    .font(WorkbenchTypography.body)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!usageQuotaStore.showAIUsageQuotas)
            .accessibilityLabel("Show Codex usage quota")

            Toggle(isOn: $usageQuotaStore.showCursorUsageQuota) {
                Text("Cursor")
                    .font(WorkbenchTypography.body)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!usageQuotaStore.showAIUsageQuotas)
            .accessibilityLabel("Show Cursor usage quota")

            Text(
                "Quota data stays on this Mac. GitMenuBar reads your local Codex and Cursor sessions "
                    + "and calls unofficial usage endpoints only when refreshing — it never stores OAuth tokens."
            )
            .font(WorkbenchTypography.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("Refresh now") {
                usageQuotaStore.refresh(reason: .manual)
            }
            .buttonStyle(.borderless)
            .font(WorkbenchTypography.detail)
            .disabled(!usageQuotaStore.showAIUsageQuotas)
        }
    }
}

#Preview("Usage Quota Settings") {
    UsageQuotaSettingsSection()
        .environmentObject(UsageQuotaStore())
        .padding()
        .frame(width: 420)
}
