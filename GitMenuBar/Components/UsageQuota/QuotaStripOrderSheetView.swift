import SwiftUI

/// Native drag-reorder surface for the menu-bar strip provider order.
struct QuotaStripOrderSheetView: View {
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(preferences.orderedProviderIDs) { providerID in
                    HStack(spacing: WorkbenchMetrics.compactSpacing) {
                        ProviderIconView(providerID: providerID)
                        Text(providerID.displayName)
                    }
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
                }
            }
        }
        .frame(minWidth: 320, minHeight: 320)
    }
}

#if DEBUG
    #Preview("Quota Strip Order") {
        QuotaStripOrderSheetView()
            .environment(UsageQuotaPresentationPreferences())
            .frame(width: 360, height: 420)
    }
#endif
