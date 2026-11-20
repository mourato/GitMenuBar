import SwiftUI

struct UsageQuotaLineMeter: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    let fillPercent: Double
    let tint: Color
    let pacePercent: Double?
    let paceDeficit: Bool
    let warningMarkerPercents: [Double]
    let workdayMarkerPercents: [Double]
    var compact = false

    private static let regularMarkerOverhang: CGFloat = 2
    private static let compactMarkerOverhang: CGFloat = 1
    private static let markerHaloWidth: CGFloat = 5
    private static let markerTickWidth: CGFloat = 2
    private static let compactMarkerHaloWidth: CGFloat = 3
    private static let compactMarkerTickWidth: CGFloat = 1
    private static let hatchSpacing: CGFloat = 4
    private static let hatchLineWidth: CGFloat = 2

    private var markerOverhang: CGFloat {
        compact ? Self.compactMarkerOverhang : Self.regularMarkerOverhang
    }

    var body: some View {
        Canvas { context, size in
            let scale = max(displayScale, 1)
            let align: (CGFloat) -> CGFloat = { value in (value * scale).rounded() / scale }
            let barHeight = max(0, size.height - 2 * markerOverhang)
            let barRect = CGRect(
                x: 0,
                y: markerOverhang,
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

            if !compact,
               let range = Self.hatchRange(
                   fillPercent: fillPercent,
                   pacePercent: pacePercent,
                   paceDeficit: paceDeficit
               )
            {
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

            if !compact {
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
            }

            if let pacePercent {
                let paceX = align(barRect.minX + barRect.width * CGFloat(Self.clampedPercent(pacePercent)) / 100)
                let haloWidth = compact ? Self.compactMarkerHaloWidth : Self.markerHaloWidth
                let halo = CGRect(
                    x: paceX - haloWidth / 2,
                    y: 0,
                    width: haloWidth,
                    height: size.height
                )
                context.blendMode = .destinationOut
                context.fill(Path(halo), with: .color(.white))
                context.blendMode = .normal
                let tickWidth = compact ? Self.compactMarkerTickWidth : Self.markerTickWidth
                let tick = CGRect(x: paceX - tickWidth / 2, y: 0, width: tickWidth, height: size.height)
                context.fill(Path(tick), with: .color(Color.primary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: (compact ? WorkbenchMetrics.quotaMeterCompactHeight : WorkbenchMetrics.quotaMeterHeight)
                + 2 * markerOverhang
        )
        .accessibilityHidden(true)
    }

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
        HStack(spacing: WorkbenchMetrics.chipSpacing) {
            UsageQuotaLineMeter(
                fillPercent: 22,
                tint: .secondary,
                pacePercent: 64,
                paceDeficit: true,
                warningMarkerPercents: [],
                workdayMarkerPercents: [],
                compact: true
            )
            .frame(width: WorkbenchMetrics.quotaMeterCompactWidth)
            UsageQuotaLineMeter(
                fillPercent: 76,
                tint: .secondary,
                pacePercent: 54,
                paceDeficit: false,
                warningMarkerPercents: [],
                workdayMarkerPercents: [],
                compact: true
            )
            .frame(width: WorkbenchMetrics.quotaMeterCompactWidth)
        }
        Text("Deficit, reserve, and used-scale deficit; marker only when pace is valid.")
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
        Text("Compact: menu-bar scale, no hatch or ticks.")
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 260)
}
