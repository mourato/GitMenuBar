import SwiftUI

/// Equal-width metric cells with one divider slot between them. In compact
/// density the five metrics share one row without dividers.
struct RepositoryOverviewMetricRowLayout: Layout {
    let density: RepositoryOverviewMetricDensity

    private var metricStride: Int {
        density == .compact ? 1 : 2
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        _ = cache
        let metricIndices = indices(in: subviews)
        let metricSizes = metricIndices.map { subviews[$0].sizeThatFits(ProposedViewSize(width: 0, height: nil)) }
        let dividerIndices = density == .compact ? [] : Array(stride(from: 1, to: subviews.count, by: metricStride))
        let dividerWidth = dividerIndices.reduce(CGFloat.zero) { width, index in
            width + subviews[index].sizeThatFits(.unspecified).width
        }
        let minimumWidth = (metricSizes.map(\.width).max() ?? 0) * CGFloat(metricSizes.count) + dividerWidth
        return CGSize(width: max(proposal.width ?? minimumWidth, minimumWidth), height: metricSizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        _ = (proposal, cache)
        let metricIndices = indices(in: subviews)
        guard !metricIndices.isEmpty else { return }
        let dividerIndices = density == .compact ? [] : Array(stride(from: 1, to: subviews.count, by: metricStride))
        let dividerWidths = dividerIndices.map { subviews[$0].sizeThatFits(.unspecified).width }
        let dividerWidth = dividerWidths.reduce(CGFloat.zero, +)
        let metricWidth = max((bounds.width - dividerWidth) / CGFloat(metricIndices.count), 0)
        var currentX = bounds.minX
        var dividerIndex = 0

        for index in metricIndices {
            subviews[index].place(
                at: CGPoint(x: currentX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: metricWidth, height: bounds.height)
            )
            currentX += metricWidth

            guard dividerIndex < dividerIndices.count else { continue }
            let divider = subviews[dividerIndices[dividerIndex]]
            let width = dividerWidths[dividerIndex]
            divider.place(
                at: CGPoint(x: currentX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            currentX += width
            dividerIndex += 1
        }
    }

    private func indices(in subviews: Subviews) -> [Int] {
        Array(stride(from: 0, to: subviews.count, by: metricStride))
    }
}
