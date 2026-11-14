import SwiftUI

/// Continuous quota meter used by the detail card rows: rounded track,
/// severity fill, deficit hatch, warning ticks, workday boundaries, and the
/// pace marker. Every number comes from `UsageQuotaPace.Reading`; this view
/// only draws, and the row that owns it carries the accessibility text.
struct UsageQuotaLineMeter: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    /// Consumed fraction of the window as displayed (remaining or used).
    let fillPercent: Double
    /// Fill color for the row's existing alert severity; `normal` stays neutral.
    let tint: Color
    /// Expected position from `UsageQuotaPace.Reading.pacePercent`; nil hides the marker.
    let pacePercent: Double?
    let paceDeficit: Bool
    /// Warning names remain consumed percents even in Remaining display.
    let warningMarkerPercents: [Double]
    let workdayMarkerPercents: [Double]

    private static let markerOverhang: CGFloat = 2
    private static let hatchSpacing: CGFloat = 4
    private static let hatchLineWidth: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let scale = max(displayScale, 1)
            let align: (CGFloat) -> CGFloat = { value in (value * scale).rounded() / scale }
            let barHeight = max(0, size.height - 2 * Self.markerOverhang)
            let barRect = CGRect(
                x: 0,
                y: Self.markerOverhang,
                width: size.width,
                height: barHeight
            )
            guard barRect.width > 0, barRect.height > 0 else { return }

            let radius = barRect.height / 2
            let barPath = Path(roundedRect: barRect, cornerRadius: radius)
            context.fill(barPath, with: .color(WorkbenchPalette.neutralBorder(contrast: contrast)))

            let fill = Self.clampedPercent(fillPercent)
            if fill > 0 {
                let fillRect = CGRect(
                    x: barRect.minX,
                    y: barRect.minY,
                    width: barRect.width * CGFloat(fill) / 100,
                    height: barRect.height
                )
                context.fill(
                    Path(roundedRect: fillRect, cornerRadius: radius),
                    with: .color(tint)
                )
            }

            if let range = Self.hatchRange(
                fillPercent: fillPercent,
                pacePercent: pacePercent,
                paceDeficit: paceDeficit
            ) {
                let hatchRect = CGRect(
                    x: barRect.minX + barRect.width * CGFloat(range.lowerBound) / 100,
                    y: barRect.minY,
                    width: barRect.width * CGFloat(range.upperBound - range.lowerBound) / 100,
                    height: barRect.height
                )
                context.drawLayer { layer in
                    layer.clip(to: barPath)
                    Self.drawHatch(
                        in: &layer,
                        rect: hatchRect,
                        opacity: contrast == .increased ? 0.8 : 0.55
                    )
                }
            }

            for percent in Self.interiorMarkerPercents(warningMarkerPercents) {
                let markerX = align(barRect.minX + barRect.width * CGFloat(percent) / 100)
                let rect = CGRect(x: markerX - 0.5, y: barRect.minY, width: 1, height: barRect.height)
                context.fill(Path(rect), with: .color(Color.primary.opacity(0.5)))
            }

            for percent in Self.interiorMarkerPercents(workdayMarkerPercents) {
                let markerX = align(barRect.minX + barRect.width * CGFloat(percent) / 100)
                let rect = CGRect(
                    x: markerX - 0.5,
                    y: barRect.minY + barRect.height / 2,
                    width: 1,
                    height: barRect.height / 2
                )
                context.fill(Path(rect), with: .color(Color.primary.opacity(0.28)))
            }

            if let pacePercent {
                let paceX = align(barRect.minX + barRect.width * CGFloat(Self.clampedPercent(pacePercent)) / 100)
                let halo = CGRect(x: paceX - 2.5, y: 0, width: 5, height: size.height)
                context.blendMode = .destinationOut
                context.fill(Path(halo), with: .color(.white))
                context.blendMode = .normal
                let tick = CGRect(x: paceX - 1, y: 0, width: 2, height: size.height)
                context.fill(Path(tick), with: .color(Color.primary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: WorkbenchMetrics.quotaMeterHeight + 2 * Self.markerOverhang)
        .accessibilityHidden(true)
    }

    /// Hatch only in a real deficit: the gap between the fill end and a valid
    /// expected-usage marker, clamped to the bar. Reserve and on-track readings
    /// return nil, and the marker must exist before anything can look behind.
    static func hatchRange(
        fillPercent: Double,
        pacePercent: Double?,
        paceDeficit: Bool
    ) -> ClosedRange<Double>? {
        guard paceDeficit, let pacePercent else { return nil }
        let lower = min(clampedPercent(fillPercent), clampedPercent(pacePercent))
        let upper = max(clampedPercent(fillPercent), clampedPercent(pacePercent))
        guard upper - lower > 0.01 else { return nil }
        return lower ... upper
    }

    static func clampedPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    /// Markers at the bar edges would double the track border, so they stay hidden.
    static func interiorMarkerPercents(_ values: [Double]) -> [Double] {
        values
            .map(clampedPercent)
            .filter { $0 > 0 && $0 < 100 }
            .reduce(into: [Double]()) { result, value in
                if !result.contains(where: { abs($0 - value) < 0.001 }) {
                    result.append(value)
                }
            }
            .sorted()
    }

    private static func drawHatch(
        in context: inout GraphicsContext,
        rect: CGRect,
        opacity: Double
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.clip(to: Path(rect))
        var stripes = Path()
        var stripeX = rect.minX - rect.height
        while stripeX < rect.maxX + rect.height {
            stripes.move(to: CGPoint(x: stripeX, y: rect.maxY))
            stripes.addLine(to: CGPoint(x: stripeX + rect.height, y: rect.minY))
            stripeX += hatchSpacing
        }
        context.stroke(
            stripes,
            with: .color(Color.primary.opacity(opacity)),
            lineWidth: hatchLineWidth
        )
    }
}

#Preview("Usage Quota Line Meter") {
    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
        UsageQuotaLineMeter(
            fillPercent: 22,
            tint: .orange,
            pacePercent: 64,
            paceDeficit: true,
            warningMarkerPercents: [20, 50],
            workdayMarkerPercents: [20, 40, 60, 80]
        )
        UsageQuotaLineMeter(
            fillPercent: 76,
            tint: .secondary,
            pacePercent: 54,
            paceDeficit: false,
            warningMarkerPercents: [],
            workdayMarkerPercents: []
        )
        UsageQuotaLineMeter(
            fillPercent: 78,
            tint: .orange,
            pacePercent: 36,
            paceDeficit: true,
            warningMarkerPercents: [50, 80],
            workdayMarkerPercents: []
        )
        Text("Deficit, reserve, and used-scale deficit; marker only when pace is valid.")
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 260)
}
