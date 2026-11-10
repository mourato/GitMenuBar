import SwiftUI

/// Status capsule for one quota provider row.
struct QuotaStatusPillView: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let status: QuotaProviderStatus

    var body: some View {
        Text(status.title)
            .font(WorkbenchTypography.caption)
            .foregroundStyle(status.textColor)
            .padding(.horizontal, WorkbenchMetrics.chipSpacing)
            .padding(.vertical, WorkbenchMetrics.headerVerticalPadding)
            .background(status.fillColor(contrast: colorSchemeContrast), in: Capsule())
    }
}

extension QuotaProviderStatus {
    var title: String {
        switch self {
        case .hidden:
            "Hidden"
        case .checking:
            "Checking"
        case .inStrip:
            "In strip"
        case .noData:
            "No data"
        case .needsKey:
            "Needs key"
        case .unavailable:
            "Unavailable"
        }
    }
}

private extension QuotaProviderStatus {
    var textColor: Color {
        switch self {
        case .inStrip:
            .green
        case .needsKey:
            .orange
        case .hidden, .checking, .noData, .unavailable:
            .secondary
        }
    }

    func fillColor(contrast: ColorSchemeContrast) -> Color {
        switch self {
        case .inStrip:
            WorkbenchPalette.successFill(contrast: contrast)
        case .needsKey:
            WorkbenchPalette.warningFill(contrast: contrast)
        case .hidden, .checking, .noData, .unavailable:
            WorkbenchPalette.hoverFill()
        }
    }
}

#if DEBUG
    #Preview("Quota Status Pills") {
        VStack(alignment: .leading, spacing: 8) {
            QuotaStatusPillView(status: .inStrip)
            QuotaStatusPillView(status: .needsKey)
            QuotaStatusPillView(status: .unavailable)
            QuotaStatusPillView(status: .hidden)
        }
        .padding()
    }
#endif
