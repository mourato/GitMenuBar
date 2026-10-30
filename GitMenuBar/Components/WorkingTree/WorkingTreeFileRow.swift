import SwiftUI

enum WorkingTreeLayoutMetrics {
    static let rowHeight: CGFloat = 32
    static let rowVerticalPadding: CGFloat = WorkbenchMetrics.headerVerticalPadding
    /// Minimum interactive target for row/header icon actions.
    static let actionHitTarget: CGFloat = WorkbenchMetrics.iconHitTarget
    static let diffColumnWidth: CGFloat = 72
    static let statusColumnWidth: CGFloat = 14
    static let trailingContentPadding: CGFloat = 12
}

struct WorkingTreeLineDiffView: View {
    let addedCount: Int
    let removedCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if addedCount > 0 {
                Text("+\(addedCount)")
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.green)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(
                        WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                        value: addedCount
                    )
            }
            if removedCount > 0 {
                Text("−\(removedCount)")
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.red)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(
                        WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                        value: removedCount
                    )
            }
        }
        .font(WorkbenchTypography.captionStrong)
        .fixedSize(horizontal: true, vertical: false)
    }
}

@MainActor
func workingTreeRowIconButton(
    systemName: String,
    help: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(WorkbenchTypography.captionStrong)
            .foregroundStyle(.primary)
            .frame(
                width: WorkingTreeLayoutMetrics.actionHitTarget,
                height: WorkingTreeLayoutMetrics.actionHitTarget
            )
            .contentShape(Rectangle())
    }
    .workbenchIcon()
    .help(help)
    .accessibilityLabel(accessibilityLabel)
}

#Preview("Working Tree Line Diff") {
    WorkingTreeLineDiffView(addedCount: 23, removedCount: 8)
        .padding()
}
