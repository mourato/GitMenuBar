import SwiftUI
import UniformTypeIdentifiers

/// Header row for one quota provider: icon, name, strip status, toggle, disclosure.
struct QuotaProviderRowView: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences

    let providerID: UsageProviderID

    @State private var isExpanded = false

    @State private var isDropTarget = false

    var body: some View {
        let order = preferences.orderedProviderIDs
        let index = order.firstIndex(of: providerID)
        row.accessibilityActions {
            if let index, index > 0 {
                Button("Move \(providerID.displayName) up") {
                    preferences.moveProvider(providerID, by: -1)
                }
            }
            if let index, index < order.count - 1 {
                Button("Move \(providerID.displayName) down") {
                    preferences.moveProvider(providerID, by: 1)
                }
            }
        }
    }

    /// Row content without reorder actions. The grip drags the provider onto
    /// another row; keyboard and VoiceOver reorder actions wrap it in `body`.
    private var row: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                dragHandle
                ProviderIconView(providerID: providerID)
                Text(providerID.displayName)
                Spacer(minLength: 0)
                if currentStatus.showsPill {
                    QuotaStatusPillView(status: currentStatus)
                        .accessibilityLabel("\(providerID.displayName) status: \(currentStatus.title)")
                }
                if currentStatus.showsPill {
                    providerToggle
                } else {
                    providerToggle
                        .accessibilityValue(Text(currentStatus.title))
                }
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
                // Hidden copies of the grip and icon keep the options aligned
                // with the provider name.
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    dragHandleGlyph.hidden()
                    ProviderIconView(providerID: providerID).hidden()
                    QuotaProviderDetailView(providerID: providerID)
                }
                .accessibilityElement(children: .contain)
            }
        }
        .opacity(usageQuotaStore.isProviderEnabled(providerID) ? 1 : 0.55)
        .contentShape(Rectangle())
        .background(isDropTarget ? WorkbenchPalette.selectedFill() : .clear, in: .rect(cornerRadius: WorkbenchMetrics.microCornerRadius))
        .dropDestination(for: UsageProviderID.self) { items, _ in
            guard let dragged = items.first,
                  dragged != providerID
            else { return false }
            preferences.moveProvider(dragged, to: providerID)
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private var dragHandleGlyph: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
    }

    private var dragHandle: some View {
        dragHandleGlyph
            .contentShape(Rectangle())
            .pointerStyle(.grabIdle)
            .draggable(providerID) {
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    ProviderIconView(providerID: providerID)
                    Text(providerID.displayName)
                }
            }
            .help("Drag to reorder")
            .accessibilityHidden(true)
    }

    private var providerToggle: some View {
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

    private var currentStatus: QuotaProviderStatus {
        let snapshot = usageQuotaStore.snapshots.first { $0.providerID == providerID }
        return QuotaProviderStatus.resolve(
            isEnabled: usageQuotaStore.isProviderEnabled(providerID),
            snapshot: snapshot,
            isKeyProvider: providerID.quotaCredentialID != nil,
            hasStoredKey: preferences.quotaKeySuffixes[providerID] != nil,
            selectedMetrics: preferences.selectedMetrics(for: providerID)
        )
    }
}

/// App-private drag payload, so only provider rows accept a dragged provider.
/// Text fields ignore it, unlike a plain-string payload.
extension UTType {
    static let quotaProvider = UTType(exportedAs: "com.mourato.GitMenuBar.quota-provider")
}

extension UsageProviderID: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .quotaProvider)
    }
}

#if DEBUG
    #Preview("Quota Provider Row") {
        Form {
            QuotaProviderRowView(providerID: .codex)
        }
        .formStyle(.grouped)
        .environment(UsageQuotaStore(providers: []))
        .environment(UsageQuotaPresentationPreferences(keyStore: InMemoryAIAPIKeyStore()))
        .frame(width: 560)
    }
#endif
