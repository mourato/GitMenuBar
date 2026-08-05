import SwiftUI

struct StaleQuotaInfoButton: View {
    @EnvironmentObject private var presentationModel: MainMenuPresentationModel
    let snapshot: UsageQuotaSnapshot

    var body: some View {
        Button {
            presentationModel.requestQuotaInfo(snapshot: snapshot)
        } label: {
            Image(systemName: "info.circle")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
        }
        .workbenchIcon()
        .help("Why is this out of date?")
        .accessibilityLabel("Why is \(snapshot.displayName) usage out of date")
    }
}

struct QuotaStaleInfoPanel: View {
    let snapshot: UsageQuotaSnapshot
    let onRetry: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text("\(snapshot.displayName) usage is out of date")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.primary)
            }

            Text(message)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Retry Now", action: onRetry)
                .workbenchSecondary()
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(width: 300, alignment: .leading)
        .workbenchPanelSurface(material: .thin)
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchMetrics.largeCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        let time = UsageQuotaFormatting.fetchedAtLabel(snapshot.fetchedAt)
        return "The last check didn't return fresh data. These numbers are from \(time). We'll retry automatically."
    }

    private var borderColor: Color {
        Color.secondary.opacity(colorSchemeContrast == .increased ? 0.6 : 0.2)
    }
}

#Preview("Quota Stale Info Button") {
    StaleQuotaInfoButton(
        snapshot: UsageQuotaSnapshot(
            providerID: .openrouter,
            displayName: "OpenRouter",
            sessionWindow: UsageWindow(remainingPercent: 42, resetAt: nil, label: "Credits"),
            weeklyWindow: nil,
            creditValueText: "$12.50 left",
            isAvailable: true,
            isStale: true,
            statusNote: "openrouter credits api"
        )
    )
    .environmentObject(MainMenuPresentationModel())
    .padding()
}

#Preview("Quota Stale Info") {
    QuotaStaleInfoPanel(
        snapshot: UsageQuotaSnapshot(
            providerID: .openrouter,
            displayName: "OpenRouter",
            sessionWindow: UsageWindow(remainingPercent: 42, resetAt: nil, label: "Credits"),
            weeklyWindow: nil,
            creditValueText: "$12.50 left",
            isAvailable: true,
            isStale: true,
            statusNote: "openrouter credits api",
            fetchedAt: Date().addingTimeInterval(-7200)
        ),
        onRetry: {}
    )
    .padding()
    .frame(width: 380)
}
