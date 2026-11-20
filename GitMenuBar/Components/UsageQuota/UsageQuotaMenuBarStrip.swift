import SwiftUI

struct UsageQuotaMenuBarStrip: View {
    let groups: [UsageQuotaMenuBarGroup]
    let style: UsageQuotaPresentationPreferences.MeterStyle
    let tint: Color

    init(
        groups: [UsageQuotaMenuBarGroup],
        style: UsageQuotaPresentationPreferences.MeterStyle,
        tint: Color = Color(nsColor: .labelColor)
    ) {
        self.groups = groups
        self.style = style
        self.tint = tint
    }

    var body: some View {
        switch style {
        case .line:
            HStack(spacing: 11) {
                ForEach(groups) { group in
                    HStack(spacing: 4) {
                        ProviderIconView(providerID: group.providerID, tint: tint)
                            .frame(width: 16, height: 16)
                        if group.readings.count > 1 {
                            VStack(alignment: .trailing, spacing: 3) {
                                ForEach(Array(group.readings.prefix(2).enumerated()), id: \.offset) { _, reading in
                                    readingView(reading)
                                }
                            }
                        } else if let reading = group.readings.first {
                            readingView(reading)
                        }
                    }
                }
            }
            .foregroundStyle(tint)
            .monospacedDigit()
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .fixedSize()
        case .text:
            HStack(spacing: 11) {
                ForEach(groups) { group in
                    HStack(spacing: 4) {
                        ProviderIconView(providerID: group.providerID, tint: tint)
                            .frame(width: 16, height: 16)
                        if group.values.count == 1 {
                            Text(group.values[0])
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            VStack(alignment: .trailing, spacing: -2) {
                                ForEach(Array(group.values.prefix(2).enumerated()), id: \.offset) { _, value in
                                    Text(value)
                                }
                            }
                            .font(.system(size: 9, weight: .semibold))
                        }
                    }
                }
            }
            .foregroundStyle(tint)
            .monospacedDigit()
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .fixedSize()
        case .bars:
            Canvas { context, size in
                let fractions = groups.flatMap(\.fractions).prefix(4)
                let count = max(1, fractions.count)
                let pad = max(1, (size.width * 0.08).rounded())
                let gap = max(1, (size.width * 0.03).rounded())
                let trackWidth = size.width - 2 * pad
                let slots = CGFloat(max(2, count))
                let trackHeight = max(1, ((size.height - 2 * pad - (slots - 1) * gap) / slots).rounded(.down))
                let total = CGFloat(count) * trackHeight + CGFloat(count - 1) * gap
                let top = pad + ((size.height - 2 * pad - total) / 2).rounded(.down)
                let radius = max(1, (trackHeight / 3).rounded(.down))

                for (index, fraction) in fractions.enumerated() {
                    let barOriginY = top + CGFloat(index) * (trackHeight + gap)
                    let track = CGRect(x: pad, y: barOriginY, width: trackWidth, height: trackHeight)
                    context.fill(Path(roundedRect: track, cornerRadius: radius), with: .color(tint.opacity(0.24)))
                    let filled = max(1, trackWidth * CGFloat(min(max(fraction, 0), 1)))
                    let fill = CGRect(x: pad, y: barOriginY, width: filled, height: trackHeight)
                    context.fill(Path(roundedRect: fill, cornerRadius: radius), with: .color(tint))
                }
            }
            .frame(width: 18, height: 18)
        case .circular:
            HStack(spacing: 11) {
                ForEach(groups) { group in
                    HStack(spacing: 4) {
                        ProviderIconView(providerID: group.providerID, tint: tint)
                            .frame(width: 16, height: 16)
                        ForEach(Array(group.fractions.prefix(2).enumerated()), id: \.offset) { _, fraction in
                            UsageQuotaCircularProgress(fraction: fraction, tint: tint)
                                .frame(width: 14, height: 14)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func readingView(_ reading: UsageQuotaMenuBarReading) -> some View {
        if let fraction = reading.fraction {
            UsageQuotaLineMeter(
                fillPercent: fraction * 100,
                tint: tint,
                pacePercent: reading.pacePercent,
                paceDeficit: reading.paceDeficit,
                warningMarkerPercents: [],
                workdayMarkerPercents: [],
                compact: true
            )
            .frame(width: WorkbenchMetrics.quotaMeterCompactWidth)
        } else {
            Text(reading.compactValue)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
        }
    }
}
