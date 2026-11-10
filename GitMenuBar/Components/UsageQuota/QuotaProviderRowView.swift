import SwiftUI

/// Header row for one quota provider: icon, name, strip status, toggle, disclosure.
struct QuotaProviderRowView: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore

    let providerID: UsageProviderID
    var keyStore: any AIAPIKeyStore = AIKeychainStore() // justified: injectable Keychain seam (real store vs in-memory previews)

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                ProviderIconView(providerID: providerID)
                Text(providerID.displayName)
                Spacer(minLength: 0)
                QuotaStatusPillView(status: currentStatus)
                    .accessibilityLabel("\(providerID.displayName) status: \(currentStatus.title)")
                Toggle(
                    "Show \(providerID.displayName)",
                    isOn: Binding(
                        get: { usageQuotaStore.isProviderEnabled(providerID) },
                        set: { usageQuotaStore.setProviderEnabled($0, for: providerID) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: WorkbenchMetrics.iconHitTarget, minHeight: WorkbenchMetrics.iconHitTarget)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide options for \(providerID.displayName)" : "Show options for \(providerID.displayName)")
            }

            if isExpanded {
                QuotaProviderDetailView(providerID: providerID, keyStore: keyStore)
            }
        }
        .opacity(usageQuotaStore.isProviderEnabled(providerID) ? 1 : 0.55)
        .disabled(!usageQuotaStore.showAIUsageQuotas)
    }

    private var currentStatus: QuotaProviderStatus {
        let snapshot = usageQuotaStore.snapshots.first { $0.providerID == providerID }
        let credentialID = providerID.quotaCredentialID
        return QuotaProviderStatus.resolve(
            isEnabled: usageQuotaStore.isProviderEnabled(providerID),
            snapshot: snapshot,
            isKeyProvider: credentialID != nil,
            hasStoredKey: hasStoredKey(credentialID: credentialID)
        )
    }

    private func hasStoredKey(credentialID: AIProviderCredentialID?) -> Bool {
        guard let credentialID,
              let stored = try? keyStore.apiKey(for: credentialID)
        else { return false }
        return !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#if DEBUG
    #Preview("Quota Provider Row") {
        Form {
            QuotaProviderRowView(providerID: .codex)
        }
        .formStyle(.grouped)
        .environment(UsageQuotaStore(providers: []))
        .environment(UsageQuotaPresentationPreferences())
        .frame(width: 560)
    }
#endif
