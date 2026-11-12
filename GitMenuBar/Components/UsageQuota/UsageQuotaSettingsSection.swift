import SwiftUI

struct UsageQuotaSettingsSection: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @State private var sessionWarningsText = ""
    @State private var weeklyWarningsText = ""
    @State private var showingPrivacyPopover = false
    @FocusState private var focusedWarningField: WarningField?

    var body: some View {
        Section {
            Toggle(
                "Show AI usage quotas",
                isOn: Binding(
                    get: { usageQuotaStore.showAIUsageQuotas },
                    set: { usageQuotaStore.showAIUsageQuotas = $0 }
                )
            )
            .toggleStyle(.switch)

            if usageQuotaStore.showAIUsageQuotas {
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    Text("Preview")
                    Spacer(minLength: 0)
                    previewContent
                }
            }
        } header: {
            SettingsFormSectionHeader(
                title: "Quotas",
                icon: "gauge.with.dots.needle.33percent"
            )
        }
        .onAppear(perform: seedWarningFields)

        if usageQuotaStore.showAIUsageQuotas {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { preferences.menuBarVisibility == .always },
                        set: { preferences.menuBarVisibility = $0 ? .always : .menuOnly }
                    )
                ) {
                    Text("Show in menu bar")
                    Text("When off, quotas appear only inside the menu.")
                }
                .toggleStyle(.switch)

                Picker(
                    "Style",
                    selection: Binding(
                        get: { preferences.meterStyle },
                        set: { preferences.meterStyle = $0 }
                    )
                ) {
                    ForEach(UsageQuotaPresentationPreferences.MeterStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(preferences.menuBarVisibility != .always)

                Picker(
                    "Show",
                    selection: Binding(
                        get: { preferences.valueStyle },
                        set: { preferences.valueStyle = $0 }
                    )
                ) {
                    ForEach(UsageQuotaPresentationPreferences.ValueStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .disabled(preferences.menuBarVisibility != .always)
            } header: {
                Text("Menu bar")
            }

            Section {
                ForEach(preferences.orderedProviderIDs) { providerID in
                    QuotaProviderRowView(providerID: providerID)
                }
            } header: {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    Text("Providers")
                    Text("Drag to set menu bar order")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            Section {
                Toggle(
                    isOn: Binding(
                        get: { preferences.showsPace },
                        set: { preferences.showsPace = $0 }
                    )
                ) {
                    Text("Show pace marker")
                    Text("Marks where usage should be at this point in the period.")
                }
                .toggleStyle(.switch)

                Picker(
                    "Workdays per week",
                    selection: Binding(
                        get: { preferences.workdaysPerWeek },
                        set: { preferences.workdaysPerWeek = $0 }
                    )
                ) {
                    ForEach(1 ... 7, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .padding(.leading, WorkbenchMetrics.rowContentInset)
                .disabled(!preferences.showsPace)

                Toggle(
                    "Show workday ticks",
                    isOn: Binding(
                        get: { preferences.workdayTickAppearance == .subtle },
                        set: { preferences.workdayTickAppearance = $0 ? .subtle : .hidden }
                    )
                )
                .toggleStyle(.switch)
                .padding(.leading, WorkbenchMetrics.rowContentInset)
                .disabled(!preferences.showsPace)

                TextField(text: $sessionWarningsText) {
                    Text("Warn during session at")
                    Text("Percent used, separated by commas.")
                }
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .focused($focusedWarningField, equals: .session)
                .onSubmit(commitSessionWarnings)

                TextField("Warn during week at", text: $weeklyWarningsText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedWarningField, equals: .weekly)
                    .onSubmit(commitWeeklyWarnings)
            } header: {
                Text("Pace and warnings")
            } footer: {
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    if let updatedAt = lastUpdatedAt {
                        Text("Updated \(updatedAt, format: .relative(presentation: .named))")
                    }
                    Button("Refresh now") {
                        usageQuotaStore.refresh(reason: .manual)
                    }
                    .buttonStyle(.borderless)
                    Spacer(minLength: 0)
                    Button {
                        showingPrivacyPopover = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Quota privacy")
                    .popover(isPresented: $showingPrivacyPopover) {
                        privacyText
                            .font(WorkbenchTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(WorkbenchMetrics.panelPadding)
                            .frame(maxWidth: WorkbenchMetrics.sidePanelWidth)
                    }
                }
                .font(WorkbenchTypography.detail)
            }
            .onChange(of: focusedWarningField) {
                commitSessionWarnings()
                commitWeeklyWarnings()
            }
        }
    }

    private enum WarningField: Hashable {
        case session
        case weekly
    }

    private var previewGroups: [UsageQuotaMenuBarGroup] {
        UsageQuotaMenuPresentation.groups(
            snapshots: usageQuotaStore.visibleSnapshots,
            preferences: preferences
        )
    }

    @ViewBuilder
    private var previewContent: some View {
        if preferences.menuBarVisibility == .menuOnly {
            Text("Shown only inside the menu")
                .foregroundStyle(.secondary)
        } else if previewGroups.isEmpty {
            Text("No quota data yet")
                .foregroundStyle(.secondary)
        } else {
            UsageQuotaMenuBarStrip(groups: previewGroups, style: preferences.meterStyle)
        }
    }

    private var lastUpdatedAt: Date? {
        usageQuotaStore.visibleSnapshots.map(\.fetchedAt).max()
    }

    private var privacyText: Text {
        Text(
            "Quota snapshots stay on this Mac. GitMenuBar uses credentials already stored by each provider "
                + "and refreshes them in place when needed. It never creates a separate OAuth token store. "
                + "OpenRouter and OpenCode Go quotas use the API keys saved in this section. Claude Code "
                + "uses its existing login to request the account quota when available. Without a saved key, OpenCode Go "
                + "falls back to OPENCODE_API_KEY from the environment and then to a local estimate "
                + "that is not account quota."
        )
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
            AntigravityUsageProvider(),
            OpenCodeGoUsageProvider(keyStore: credentialStore)
        ]

        Form {
            UsageQuotaSettingsSection()
        }
        .formStyle(.grouped)
        .environment(UsageQuotaStore(providers: providers))
        .environment(UsageQuotaPresentationPreferences())
        .frame(width: 560, height: 280)
    }

#endif
