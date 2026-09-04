import SwiftUI

/// Shared inspector title block: project name plus the active selection title.
struct InspectorHeaderView: View {
    let projectName: String
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: WorkbenchMetrics.compactSpacing) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(projectName)
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(title)
                    .font(WorkbenchTypography.windowTitle)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview("Inspector Header") {
    InspectorHeaderView(projectName: "GitMenuBar", title: "Working Tree")
        .frame(width: WorkbenchMetrics.inspectorMinimumWidth)
        .padding()
}
