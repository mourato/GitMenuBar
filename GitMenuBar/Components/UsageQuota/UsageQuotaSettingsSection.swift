import SwiftUI

struct UsageQuotaSettingsSection: View {
    @EnvironmentObject private var usageQuotaStore: UsageQuotaStore
    @EnvironmentObject private var preferences: UsageQuotaPresentationPreferences
    @State private var sessionWarningsText = ""
    @State private var weeklyWarningsText = ""

    var body: some View {
        Toggle("Show AI usage quotas", isOn: $usageQuotaStore.showAIUsageQuotas)
            .toggleStyle(.switch)

        Picker("Status item", selection: $preferences.menuBarVisibility) {
            ForEach(UsageQuotaPresentationPreferences.MenuBarVisibility.allCases) { visibility in
                Text(visibility.title).tag(visibility)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!usageQuotaStore.showAIUsageQuotas)

        Picker("Figures", selection: $preferences.meterStyle) {
            ForEach(UsageQuotaPresentationPreferences.MeterStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!usageQuotaStore.showAIUsageQuotas)

        Picker("Count", selection: $preferences.valueStyle) {
            ForEach(UsageQuotaPresentationPreferences.ValueStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!usageQuotaStore.showAIUsageQuotas)

        Toggle("Show pace markers", isOn: $preferences.showsPace)
            .toggleStyle(.switch)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        Stepper(
            "Workdays per week: \(preferences.workdaysPerWeek)",
            value: $preferences.workdaysPerWeek,
            in: 1 ... 7
        )
        .disabled(!usageQuotaStore.showAIUsageQuotas)

        Picker("Workday ticks", selection: $preferences.workdayTickAppearance) {
            ForEach(UsageQuotaPresentationPreferences.WorkdayTickAppearance.allCases) { appearance in
                Text(appearance.title).tag(appearance)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!usageQuotaStore.showAIUsageQuotas)

        TextField("Session warnings", text: $sessionWarningsText)
            .onSubmit(commitSessionWarnings)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        TextField("Weekly warnings", text: $weeklyWarningsText)
            .onSubmit(commitWeeklyWarnings)
            .disabled(!usageQuotaStore.showAIUsageQuotas)

        Text("Warning markers draw at consumed percents, for example 50, 80. Press Return to apply.")
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        ForEach(Array(preferences.orderedProviderIDs.enumerated()), id: \.element) { index, providerID in
            providerRow(providerID, index: index)
        }
        .onAppear(perform: seedWarningFields)

        Text(
            "Quota snapshots stay on this Mac. GitMenuBar uses credentials already stored by each provider "
                + "and refreshes them in place when needed. It never creates a separate OAuth token store. "
                + "OpenRouter quota uses the provider credential configured in AI settings. Claude Code "
                + "uses its existing login to request the account quota when available."
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

    private func providerRow(_ providerID: UsageProviderID, index: Int) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                ProviderIconView(providerID: providerID)
                Text(providerID.displayName)
                Spacer(minLength: 0)
                Button {
                    preferences.moveProvider(providerID, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Move \(providerID.displayName) up")
                .disabled(index == 0)

                Button {
                    preferences.moveProvider(providerID, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Move \(providerID.displayName) down")
                .disabled(index == preferences.orderedProviderIDs.count - 1)

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
            }

            Menu {
                ForEach(UsageQuotaPresentationPreferences.Metric.allCases) { metric in
                    Button {
                        preferences.toggleMetric(metric, for: providerID)
                    } label: {
                        Label(
                            metric.title,
                            systemImage: preferences.selectedMetrics(for: providerID).contains(metric)
                                ? "checkmark"
                                : ""
                        )
                    }
                }
            } label: {
                HStack {
                    Text("Menu bar")
                    Spacer()
                    Text(selectedMetricsLabel(for: providerID))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .disabled(!usageQuotaStore.showAIUsageQuotas || !usageQuotaStore.isProviderEnabled(providerID))
        }
        .opacity(usageQuotaStore.isProviderEnabled(providerID) ? 1 : 0.55)
        .disabled(!usageQuotaStore.showAIUsageQuotas)
    }

    private func selectedMetricsLabel(for providerID: UsageProviderID) -> String {
        let metrics = preferences.selectedMetrics(for: providerID)
        return metrics.isEmpty ? "Mark only" : metrics.map(\.title).joined(separator: ", ")
    }

    private func seedWarningFields() {
        sessionWarningsText = UsageQuotaPace.canonicalThresholdsText(preferences.sessionWarningThresholds)
        weeklyWarningsText = UsageQuotaPace.canonicalThresholdsText(preferences.weeklyWarningThresholds)
    }

    private func commitSessionWarnings() {
        preferences.setSessionWarningThresholds(from: sessionWarningsText)
        sessionWarningsText = UsageQuotaPace.canonicalThresholdsText(preferences.sessionWarningThresholds)
    }

    private func commitWeeklyWarnings() {
        preferences.setWeeklyWarningThresholds(from: weeklyWarningsText)
        weeklyWarningsText = UsageQuotaPace.canonicalThresholdsText(preferences.weeklyWarningThresholds)
    }
}

#if DEBUG
    #Preview("Usage Quota Settings") {
        let credentialStore = InMemoryAIAPIKeyStore()
        let providers: [any UsageQuotaProviding] = [
            ClaudeCodeUsageProvider(),
            CodexUsageProvider(),
            CursorUsageProvider(),
            OpenRouterUsageProvider(keyStore: credentialStore),
            GeminiUsageProvider(),
            AntigravityUsageProvider()
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
        .environmentObject(UsageQuotaPresentationPreferences())
        .frame(width: 560, height: 280)
    }

#endif
