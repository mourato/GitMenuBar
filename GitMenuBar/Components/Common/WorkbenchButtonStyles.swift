import SwiftUI

// MARK: - Primary

extension View {
    func workbenchPrimary(isMuted: Bool = false) -> some View {
        controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(isMuted ? .gray.opacity(0.75) : nil)
    }
}

// MARK: - Secondary

extension View {
    func workbenchSecondary() -> some View {
        buttonStyle(.bordered)
    }
}

// MARK: - Ghost

extension View {
    func workbenchGhost() -> some View {
        buttonStyle(.borderless)
            .font(WorkbenchTypography.detail)
    }
}

// MARK: - Icon

extension View {
    func workbenchIcon() -> some View {
        buttonStyle(.borderless)
            .controlSize(.small)
            .frame(minWidth: WorkbenchMetrics.iconHitTarget, minHeight: WorkbenchMetrics.iconHitTarget)
    }
}

// MARK: - Row

extension View {
    func workbenchRow(isSelected: Bool = false) -> some View {
        buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? WorkbenchPalette.selectedFill() : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
    }
}

// MARK: - Destructive row

extension View {
    func workbenchDestructiveRow() -> some View {
        buttonStyle(.borderless)
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Workbench Button Variants") {
    WorkbenchButtonVariantsPreviewMatrix()
        .padding(WorkbenchMetrics.panelPadding)
        .frame(width: 360)
}

private struct WorkbenchButtonVariantsPreviewMatrix: View {
    @State private var selectedRow = false

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            Button("Commit") {}
                .frame(maxWidth: .infinity)
                .workbenchPrimary()

            Button("Cancel") {}
                .workbenchSecondary()

            HStack {
                Button("Split") {}
                    .workbenchGhost()
                Spacer()
                Button("Branches") {}
                    .workbenchGhost()
            }

            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Button {} label: {
                    Image(systemName: "ellipsis.circle")
                        .font(WorkbenchTypography.body)
                }
                .workbenchIcon()
                .accessibilityLabel("Repository options")

                Button {} label: {
                    Image(systemName: "gearshape")
                        .font(WorkbenchTypography.body)
                }
                .workbenchIcon()
                .accessibilityLabel("Settings")
            }

            Button {
                selectedRow.toggle()
            } label: {
                HStack {
                    Text("feature/workbench-buttons")
                        .font(WorkbenchTypography.body)
                    Spacer()
                    if selectedRow {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .workbenchRow(isSelected: selectedRow)

            Button(role: .destructive) {} label: {
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    Image(systemName: "trash")
                    Text("Delete Repository")
                        .font(WorkbenchTypography.body)
                    Spacer()
                }
            }
            .workbenchDestructiveRow()
        }
    }
}
