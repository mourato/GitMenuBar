import SwiftUI

struct WorkbenchSectionHeaderChrome<Trailing: View>: View {
    let title: String
    @Binding var isCollapsed: Bool
    let accessibilityLabel: String
    let accessibilityHintExpanded: String
    let accessibilityHintCollapsed: String
    @ViewBuilder let trailing: (_ isHovered: Bool) -> Trailing

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Button {
                withAnimation(
                    WorkbenchMotion.adaptive(WorkbenchMotion.settle, usesReducedMotion: reduceMotion)
                ) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: WorkbenchMetrics.chipSpacing) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundColor(.secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))

                    Text(title)
                        .font(WorkbenchTypography.body)
                        .tracking(WorkbenchTypography.tracking(for: .subheadline))
                }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isCollapsed ? accessibilityHintExpanded : accessibilityHintCollapsed)

            Spacer(minLength: WorkbenchMetrics.compactSpacing)

            trailing(isHovered)
        }
        .padding(.vertical, WorkbenchMetrics.headerVerticalPadding)
        .padding(.horizontal, WorkbenchMetrics.microSpacing)
        .background(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
        .cornerRadius(WorkbenchMetrics.rowCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius)
                .stroke(
                    WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast)
                        .opacity(colorSchemeContrast == .increased ? 1 : 0),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .animation(
            WorkbenchMotion.adaptive(WorkbenchMotion.micro, usesReducedMotion: reduceMotion),
            value: isHovered
        )
        .onHover { inside in
            isHovered = inside
        }
    }
}

private struct SectionHeaderChromePreview: View {
    @State private var isHistoryCollapsed = false
    @State private var isStagedCollapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            WorkbenchSectionHeaderChrome(
                title: "History",
                isCollapsed: $isHistoryCollapsed,
                accessibilityLabel: "History section",
                accessibilityHintExpanded: "Expands commit history.",
                accessibilityHintCollapsed: "Collapses commit history."
            ) { _ in
                Text("42")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            WorkbenchSectionHeaderChrome(
                title: "Staged",
                isCollapsed: $isStagedCollapsed,
                accessibilityLabel: "Staged section",
                accessibilityHintExpanded: "Expands the section.",
                accessibilityHintCollapsed: "Collapses the section."
            ) { _ in
                HStack(spacing: WorkbenchMetrics.microSpacing) {
                    WorkingTreeLineDiffView(addedCount: 23, removedCount: 8)

                    Button(action: {}, label: {
                        Image(systemName: "minus.circle")
                            .font(WorkbenchTypography.captionStrong)
                            .foregroundColor(.primary)
                            .frame(
                                width: WorkingTreeLayoutMetrics.actionHitTarget,
                                height: WorkingTreeLayoutMetrics.actionHitTarget
                            )
                            .contentShape(Rectangle())
                    })
                    .workbenchIcon()
                    .help("Unstage all files")

                    Text("3 files")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 380, alignment: .leading)
    }
}

#Preview("Workbench Section Header Chrome") {
    SectionHeaderChromePreview()
}
