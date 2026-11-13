import SwiftUI

struct InlinePageHeader: View {
    let title: String
    let icon: LucideIconName
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                LucideIconView(name: icon)
                    .foregroundStyle(Color.accentColor)
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
        icon: .circlePlus,
        actionTitle: "Cancel",
        onAction: {}
    )
    .padding()
    .frame(width: 360)
}
