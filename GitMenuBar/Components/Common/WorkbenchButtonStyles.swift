import AppKit
import SwiftUI

// MARK: - Primary

extension View {
    /// Focal panel action — `.borderedProminent` at large control size.
    func workbenchPrimary(isMuted: Bool = false) -> some View {
        controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(isMuted ? .gray.opacity(0.75) : nil)
    }
}

// MARK: - Secondary

extension View {
    /// Alternate confirm / bordered action — quieter than Primary on the same surface.
    func workbenchSecondary() -> some View {
        buttonStyle(.bordered)
            .pressable()
    }
}

// MARK: - Ghost

extension View {
    /// Low-emphasis chrome — borderless detail text with shared press feedback.
    func workbenchGhost() -> some View {
        buttonStyle(.borderless)
            .font(WorkbenchTypography.detail)
            .pressable()
    }
}

// MARK: - Icon

struct WorkbenchIconButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                minWidth: WorkbenchMetrics.iconHitTarget,
                minHeight: WorkbenchMetrics.iconHitTarget
            )
            .background(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .fill(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.press, usesReducedMotion: reduceMotion),
                value: configuration.isPressed
            )
            .onHover { inside in
                isHovered = inside
            }
    }
}

extension ButtonStyle where Self == WorkbenchIconButtonStyle {
    static var workbenchIcon: WorkbenchIconButtonStyle {
        WorkbenchIconButtonStyle()
    }
}

extension View {
    func workbenchIcon() -> some View {
        buttonStyle(.workbenchIcon)
    }
}

// MARK: - Row

struct WorkbenchRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.press, usesReducedMotion: reduceMotion),
                value: configuration.isPressed
            )
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
                value: isHovered
            )
            .onHover { inside in
                isHovered = inside
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var rowFill: Color {
        if isSelected {
            return WorkbenchPalette.selectedFill()
        }
        if isHovered {
            return WorkbenchPalette.hoverFill()
        }
        return .clear
    }
}

extension ButtonStyle where Self == WorkbenchRowButtonStyle {
    static func workbenchRow(isSelected: Bool = false) -> WorkbenchRowButtonStyle {
        WorkbenchRowButtonStyle(isSelected: isSelected)
    }
}

extension View {
    func workbenchRow(isSelected: Bool = false) -> some View {
        buttonStyle(.workbenchRow(isSelected: isSelected))
    }
}

// MARK: - Destructive row

struct WorkbenchDestructiveRowButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .fill(isHovered ? WorkbenchPalette.errorFill(contrast: colorSchemeContrast) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.press, usesReducedMotion: reduceMotion),
                value: configuration.isPressed
            )
            .animation(
                WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
                value: isHovered
            )
            .onHover { inside in
                isHovered = inside
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

extension ButtonStyle where Self == WorkbenchDestructiveRowButtonStyle {
    static var workbenchDestructiveRow: WorkbenchDestructiveRowButtonStyle {
        WorkbenchDestructiveRowButtonStyle()
    }
}

extension View {
    func workbenchDestructiveRow() -> some View {
        buttonStyle(.workbenchDestructiveRow)
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
                Button("Atomic Commits") {}
                    .workbenchGhost()
                Spacer()
                Button("Manage…") {}
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
                    Text("Delete Repository…")
                        .font(WorkbenchTypography.body)
                    Spacer()
                }
            }
            .workbenchDestructiveRow()
        }
    }
}
