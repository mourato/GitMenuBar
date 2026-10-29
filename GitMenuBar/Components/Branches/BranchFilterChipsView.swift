import SwiftUI

struct BranchFilterChipsView: View {
    @Binding var filter: BranchFilter
    let model: BranchListModel

    var body: some View {
        HStack(spacing: WorkbenchMetrics.chipSpacing) {
            ForEach(BranchFilter.allCases, id: \.self) { item in
                let count = model.count(for: item)
                let isSelected = filter == item
                Button {
                    withAnimation(WorkbenchMotion.swap) {
                        filter = item
                    }
                } label: {
                    HStack(spacing: WorkbenchMetrics.microSpacing) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption2.bold())
                                .accessibilityHidden(true)
                        }
                        Text(item.title).bold(isSelected)
                        Text("\(count)")
                            .monospacedDigit()
                            .bold(isSelected)
                            .opacity(isSelected ? 0.9 : 0.6)
                    }
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
                    .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.15) : WorkbenchPalette.hoverFill()))
                    .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1))
                    .frame(minHeight: WorkbenchMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title), \(count) \(count == 1 ? "branch" : "branches")")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Branch filter")
    }
}

#Preview("Branch Filter Chips") {
    BranchFilterChipsView(
        filter: .constant(.all),
        model: BranchListModel(
            current: nil,
            local: [],
            visible: [],
            collapsedMerged: [],
            remoteGroups: [],
            ungroupedRemote: [],
            readyCount: 0,
            blockedCount: 0,
            filterCounts: [.all: 5, .mergeable: 2, .dirty: 1, .stale: 0]
        )
    )
    .padding()
}
