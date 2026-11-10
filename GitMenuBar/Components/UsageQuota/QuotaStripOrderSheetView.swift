import SwiftUI

/// Native drag-reorder surface for the menu-bar strip provider order.
struct QuotaStripOrderSheetView: View {
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let order = preferences.orderedProviderIDs
                ForEach(Array(order.enumerated()), id: \.element) { index, providerID in
                    orderRow(
                        for: providerID,
                        isFirst: index == 0,
                        isLast: index == order.count - 1
                    )
                }
                .onMove { offsets, destination in
                    preferences.moveProvider(from: offsets, to: destination)
                }
            }
            .listStyle(.inset)
            .navigationTitle("Strip order")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 320)
    }

    /// Row with keyboard and VoiceOver reorder actions. Drag handles cover
    /// pointer users; these cover everyone else.
    @ViewBuilder
    private func orderRow(for providerID: UsageProviderID, isFirst: Bool, isLast: Bool) -> some View {
        let row = HStack(spacing: WorkbenchMetrics.compactSpacing) {
            ProviderIconView(providerID: providerID)
            Text(providerID.displayName)
        }
        if !isFirst, !isLast {
            row
                .accessibilityAction(named: Text("Move \(providerID.displayName) up")) {
                    preferences.moveProvider(providerID, by: -1)
                }
                .accessibilityAction(named: Text("Move \(providerID.displayName) down")) {
                    preferences.moveProvider(providerID, by: 1)
                }
        } else if !isFirst {
            row
                .accessibilityAction(named: Text("Move \(providerID.displayName) up")) {
                    preferences.moveProvider(providerID, by: -1)
                }
        } else if !isLast {
            row
                .accessibilityAction(named: Text("Move \(providerID.displayName) down")) {
                    preferences.moveProvider(providerID, by: 1)
                }
        } else {
            row
        }
    }
}

#if DEBUG
    #Preview("Quota Strip Order") {
        QuotaStripOrderSheetView()
            .environment(UsageQuotaPresentationPreferences(keyStore: InMemoryAIAPIKeyStore()))
            .frame(width: 360, height: 420)
    }
#endif
