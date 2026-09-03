import SwiftUI

struct MainMenuInspectorView: View {
    let projectName: String
    let selection: MainMenuInspectorSelection?
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
                HStack(alignment: .top, spacing: WorkbenchMetrics.compactSpacing) {
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                        Text(projectName)
                            .font(WorkbenchTypography.captionStrong)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(selection?.title ?? "Details")
                            .font(WorkbenchTypography.windowTitle)
                            .lineLimit(2)
                            .accessibilityAddTraits(.isHeader)
                    }

                    Spacer(minLength: 0)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                    .accessibilityLabel("Close details")
                }

                if let selection {
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                        Text("Selected item")
                            .font(WorkbenchTypography.sectionLabel)
                        Text(selection.id)
                            .font(WorkbenchTypography.detail)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(WorkbenchMetrics.panelPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .workbenchPanelSurface(
                        cornerRadius: WorkbenchMetrics.cornerRadius,
                        material: .thin
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                            .stroke(WorkbenchPalette.neutralBorder(contrast: .standard), lineWidth: 1)
                    }
                } else {
                    ContentUnavailableView(
                        "No details selected",
                        systemImage: "sidebar.right",
                        description: Text("Select an item in the workbench to view its details.")
                    )
                }
            }
            .padding(WorkbenchMetrics.panelPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Details")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selection.map { "Details for \($0.title)" } ?? "Details")
    }
}

#Preview("No Selection") {
    MainMenuInspectorView(
        projectName: "GitMenuBar",
        selection: nil,
        onClose: {}
    )
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

#Preview("File Details") {
    MainMenuInspectorView(
        projectName: "GitMenuBar",
        selection: .stagedFile(path: "Sources/App.swift"),
        onClose: {}
    )
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}

#Preview("Commit Details") {
    MainMenuInspectorView(
        projectName: "GitMenuBar",
        selection: .commit(id: "abc123def456"),
        onClose: {}
    )
    .frame(width: WorkbenchMetrics.inspectorMinimumWidth, height: 360)
}
