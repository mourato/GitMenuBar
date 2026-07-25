import SwiftUI

struct InlinePageHeader: View {
    let title: String
    let systemImage: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                Image(systemName: systemImage)
                    .font(WorkbenchTypography.windowTitle)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(WorkbenchTypography.windowTitle)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

            Button(actionTitle, action: onAction)
                .workbenchGhost()
        }
        .padding(.top, WorkbenchMetrics.microSpacing)
    }
}

#Preview("Inline Page Header") {
    InlinePageHeader(
        title: "Create Repository",
        systemImage: "plus.circle.fill",
        actionTitle: "Cancel",
        onAction: {}
    )
    .padding()
    .frame(width: 360)
}
