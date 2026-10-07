import SwiftUI

/// Text styling for a meter row; each surface passes its own typography.
struct UsageQuotaMeterRowStyle {
    let titleFont: Font
    let supportingFont: Font
    let primary: Color
    let secondary: Color
}

/// Single-Canvas quota bar: track, fill, pace-tip punch-out, warning marker
/// punches, workday ticks. Everything draws in one Canvas pass so no
/// compositingGroup or blendMode view modifiers are needed. Markers are
/// decorative; the bar carries an accessibility label and value instead.
struct UsageQuotaMeterBar: View {
    private enum MarkerKind {
        case quotaWarning
        case workdayBoundary
    }

    private struct BarMarker {
        let percent: Double
        let kind: MarkerKind
    }

    private static let paceStripeCount = 3
    private static let stripePunchOpacity = 0.9
    private static let warningMarkerPunchWidth: CGFloat = 5
    private static let warningMarkerStripeWidth: CGFloat = 1

    let percent: Double
    let tint: Color
    let trackColor: Color
    let accessibilityLabel: String
    let accessibilityValue: String
    let pacePercent: Double?
    let paceDeficit: Bool
    let warningMarkerPercents: [Double]
    let workdayMarkerPercents: [Double]
    let workdayTickAppearance: UsageQuotaPresentationPreferences.WorkdayTickAppearance
    let height: CGFloat

    @Environment(\.displayScale) private var displayScale

    init(
        percent: Double,
        tint: Color,
        trackColor: Color,
        accessibilityLabel: String,
        accessibilityValue: String,
        pacePercent: Double? = nil,
        paceDeficit: Bool = false,
        warningMarkerPercents: [Double] = [],
        workdayMarkerPercents: [Double] = [],
        workdayTickAppearance: UsageQuotaPresentationPreferences.WorkdayTickAppearance = .subtle,
        height: CGFloat = 5
    ) {
        self.percent = percent
        self.tint = tint
        self.trackColor = trackColor
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.pacePercent = pacePercent
        self.paceDeficit = paceDeficit
        self.warningMarkerPercents = warningMarkerPercents
        self.workdayMarkerPercents = workdayMarkerPercents
        self.workdayTickAppearance = workdayTickAppearance
        self.height = height
    }

    var body: some View {
        Canvas { context, size in
            let scale = max(displayScale, 1)
            let fillPercent = Self.renderedFillPercent(percent)
            let fillWidth = size.width * fillPercent / 100
            let paceWidth = size.width * Self.clampedPercent(pacePercent) / 100
            let tipWidth = max(25, size.height * 6.5)
            let stripeInset = 1 / scale
            let tipOffset = paceWidth - tipWidth + (Self.paceStripeSpan(for: scale) / 2) + stripeInset
            let showTip = pacePercent != nil && tipWidth > 0.5
            let markers = Self.resolvedMarkers(
                warningPercents: warningMarkerPercents,
                workdayPercents: workdayMarkerPercents,
                workdayAppearance: workdayTickAppearance
            )

            let cornerRadius = size.height / 2
            let cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
            let rect = CGRect(origin: .zero, size: size)

            context.clip(to: Path(rect))

            let trackPath = Path { path in path.addRoundedRect(in: rect, cornerSize: cornerSize) }
            context.fill(trackPath, with: .color(trackColor))

            if fillWidth > 0 {
                let fillRect = CGRect(x: 0, y: 0, width: min(fillWidth, size.width), height: size.height)
                let fillPath = Path { path in path.addRoundedRect(in: fillRect, cornerSize: cornerSize) }
                context.fill(fillPath, with: .color(tint))
            }

            for marker in markers {
                let centerX = size.width * marker.percent / 100
                switch marker.kind {
                case .quotaWarning:
                    let markerRect = Self.warningMarkerRect(centerX: centerX, size: size, scale: scale)
                    let stripeRect = Self.warningMarkerStripeRect(markerRect, scale: scale)
                    let punchPath = Path { path in
                        path.addRect(Self.extendedMarkerRect(markerRect, size: size))
                    }
                    let stripePath = Path { path in
                        path.addRect(Self.extendedMarkerRect(stripeRect, size: size))
                    }
                    context.blendMode = .destinationOut
                    context.fill(punchPath, with: .color(.white.opacity(Self.stripePunchOpacity)))
                    context.blendMode = .normal
                    context.fill(stripePath, with: .color(.primary.opacity(0.68)))
                case .workdayBoundary:
                    let tickRect = Self.workdayMarkerRect(centerX: centerX, size: size, scale: scale)
                    context.fill(Path(tickRect), with: .color(.primary.opacity(0.30)))
                }
            }

            if showTip {
                let stripeColor: Color = paceDeficit ? .red : .green
                let tipSize = CGSize(width: tipWidth, height: size.height)
                let stripes = Self.paceStripePaths(size: tipSize, scale: scale)
                let shift = CGAffineTransform(translationX: tipOffset, y: 0)
                context.blendMode = .destinationOut
                context.fill(stripes.punched.applying(shift), with: .color(.white.opacity(Self.stripePunchOpacity)))
                context.blendMode = .normal
                context.fill(stripes.center.applying(shift), with: .color(stripeColor))
            }
        }
        .frame(height: height)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private static func paceStripeWidth(for _: CGFloat) -> CGFloat {
        2
    }

    private static func paceStripeSpan(for scale: CGFloat) -> CGFloat {
        let stripeCount = max(1, Self.paceStripeCount)
        return Self.paceStripeWidth(for: scale) * CGFloat(stripeCount)
    }

    private static func resolvedMarkers(
        warningPercents: [Double],
        workdayPercents: [Double],
        workdayAppearance: UsageQuotaPresentationPreferences.WorkdayTickAppearance
    ) -> [BarMarker] {
        let warnings = normalizedMarkerPercents(warningPercents)
        let workdays: [Double] = if workdayAppearance == .hidden {
            []
        } else {
            normalizedMarkerPercents(workdayPercents)
                .filter { workday in !warnings.contains { abs($0 - workday) < 0.001 } }
        }
        return (
            warnings.map { BarMarker(percent: $0, kind: .quotaWarning) } +
                workdays.map { BarMarker(percent: $0, kind: .workdayBoundary) }
        )
        .sorted { lhs, rhs in lhs.percent < rhs.percent }
    }

    private static func normalizedMarkerPercents(_ values: [Double]) -> [Double] {
        values
            .map(clampedPercent)
            .filter { $0 > 0 && $0 < 100 }
            .reduce(into: [Double]()) { result, value in
                if !result.contains(where: { abs($0 - value) < 0.001 }) {
                    result.append(value)
                }
            }
    }

    /// Aligns edge rendering with the rounded percent label: sub-0.5% is empty, 99.5%+ is full.
    static func renderedFillPercent(_ percent: Double) -> Double {
        let clamped = clampedPercent(percent)
        let displayed = Int(clamped.rounded())
        if displayed <= 0 {
            return 0
        }
        if displayed >= 100 {
            return 100
        }
        return clamped
    }

    private static func paceStripePaths(size: CGSize, scale: CGFloat) -> (punched: Path, center: Path) {
        let rect = CGRect(origin: .zero, size: size)
        let extend = size.height * 2
        let stripeMinY = ((0 - extend) * scale).rounded() / scale
        let stripeMaxY = ((size.height + extend) * scale).rounded() / scale
        let align: (CGFloat) -> CGFloat = { value in
            (value * scale).rounded() / scale
        }

        let stripeWidth = Self.paceStripeWidth(for: scale)
        let punchWidth = stripeWidth * 3
        let stripeInset = 1 / scale
        let anchorX = align(rect.maxX - stripeInset)
        var punchedStripe = Path()
        var centerStripe = Path()
        guard anchorX - punchWidth - rect.minX >= 0 else {
            return (punchedStripe, centerStripe)
        }

        let punchRightX = align(anchorX)
        let punchLeftX = punchRightX - punchWidth
        punchedStripe.addPath(Path { path in
            path.move(to: CGPoint(x: punchLeftX, y: stripeMinY))
            path.addLine(to: CGPoint(x: punchRightX, y: stripeMinY))
            path.addLine(to: CGPoint(x: punchRightX, y: stripeMaxY))
            path.addLine(to: CGPoint(x: punchLeftX, y: stripeMaxY))
            path.closeSubpath()
        })

        let centerLeftX = align(punchLeftX + (punchWidth - stripeWidth) / 2)
        let centerRightX = centerLeftX + stripeWidth
        centerStripe.addPath(Path { path in
            path.move(to: CGPoint(x: centerLeftX, y: stripeMinY))
            path.addLine(to: CGPoint(x: centerRightX, y: stripeMinY))
            path.addLine(to: CGPoint(x: centerRightX, y: stripeMaxY))
            path.addLine(to: CGPoint(x: centerLeftX, y: stripeMaxY))
            path.closeSubpath()
        })

        return (punchedStripe, centerStripe)
    }

    private static func warningMarkerRect(centerX: CGFloat, size: CGSize, scale rawScale: CGFloat) -> CGRect {
        let scale = max(rawScale, 1)
        let width = Self.warningMarkerPunchWidth
        let align: (CGFloat) -> CGFloat = { value in
            (value * scale).rounded() / scale
        }
        return CGRect(
            x: align(centerX - width / 2),
            y: 0,
            width: width,
            height: align(size.height)
        )
    }

    private static func warningMarkerStripeRect(_ markerRect: CGRect, scale rawScale: CGFloat) -> CGRect {
        let scale = max(rawScale, 1)
        let width = min(markerRect.width, max(1 / scale, Self.warningMarkerStripeWidth))
        let align: (CGFloat) -> CGFloat = { value in
            (value * scale).rounded() / scale
        }
        return CGRect(
            x: align(markerRect.midX - width / 2),
            y: markerRect.minY,
            width: width,
            height: markerRect.height
        )
    }

    private static func workdayMarkerRect(centerX: CGFloat, size: CGSize, scale rawScale: CGFloat) -> CGRect {
        let scale = max(rawScale, 1)
        let width = 1 / scale
        let height = max(1 / scale, size.height * 0.5)
        let align: (CGFloat) -> CGFloat = { value in
            (value * scale).rounded() / scale
        }
        return CGRect(
            x: align(centerX - width / 2),
            y: align(size.height - height),
            width: width,
            height: align(height)
        )
    }

    private static func extendedMarkerRect(_ rect: CGRect, size: CGSize) -> CGRect {
        let extend = size.height * 2
        return rect.insetBy(dx: 0, dy: -extend)
    }

    private static func clampedPercent(_ value: Double?) -> Double {
        guard let value else {
            return 0
        }
        return min(100, max(0, value))
    }
}

/// Shared quota row: header (title plus reset text), bar, pace meta line,
/// detail line. Pure rendering; the `reading` carries all computed content.
struct UsageQuotaMeterRow: View {
    let title: String
    let reading: UsageQuotaPace.Reading
    let style: UsageQuotaMeterRowStyle
    let tint: Color
    let trackColor: Color
    let barHeight: CGFloat
    let accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(title) \(reading.percentText)")
                    .font(style.titleFont)
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let resetText = reading.resetText {
                    Text(resetText)
                        .font(style.supportingFont)
                        .foregroundStyle(style.secondary)
                        .monospacedDigit()
                }
            }
            UsageQuotaMeterBar(
                percent: reading.fillPercent,
                tint: tint,
                trackColor: trackColor,
                accessibilityLabel: accessibilityLabel,
                accessibilityValue: accessibilityValue,
                pacePercent: reading.pacePercent,
                paceDeficit: reading.paceDeficit,
                warningMarkerPercents: reading.warningMarkerPercents,
                workdayMarkerPercents: reading.workdayMarkerPercents,
                height: barHeight
            )
            .accessibilityHidden(true)
            if reading.paceLeftText != nil || reading.paceRightText != nil {
                HStack(spacing: 8) {
                    if let leftText = reading.paceLeftText {
                        Text(leftText)
                    }
                    Spacer(minLength: 8)
                    if let rightText = reading.paceRightText {
                        Text(rightText)
                    }
                }
                .font(style.supportingFont)
                .foregroundStyle(style.secondary)
                .monospacedDigit()
            }
            if let detailText = reading.detailText {
                Text(detailText)
                    .font(style.supportingFont)
                    .foregroundStyle(style.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        [
            reading.percentText,
            reading.paceLeftText,
            reading.paceRightText,
            reading.detailText
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
    }
}

#Preview("Usage Quota Meter Row") {
    let window = UsageWindow(
        remainingPercent: 42,
        resetAt: Date().addingTimeInterval(3600 * 3),
        label: "5h",
        durationSeconds: 5 * 3600
    )
    let style = UsageQuotaMeterRowStyle(
        titleFont: .callout.weight(.semibold),
        supportingFont: .caption,
        primary: .primary,
        secondary: .secondary
    )
    VStack(alignment: .leading, spacing: 16) {
        UsageQuotaMeterRow(
            title: "Session",
            reading: UsageQuotaPace.reading(
                for: window,
                showUsed: false,
                thresholds: [50, 80],
                workdaysPerWeek: 5,
                showPace: true
            ),
            style: style,
            tint: .orange,
            trackColor: Color.primary.opacity(0.08),
            barHeight: 5,
            accessibilityLabel: "Codex Session"
        )
        UsageQuotaMeterRow(
            title: "Weekly",
            reading: UsageQuotaPace.reading(
                for: UsageWindow(
                    remainingPercent: 88,
                    resetAt: Date().addingTimeInterval(86400 * 3),
                    label: "7d",
                    durationSeconds: 7 * 86400
                ),
                showUsed: true,
                thresholds: [50, 80],
                workdaysPerWeek: 5,
                showPace: true
            ),
            style: style,
            tint: .green,
            trackColor: Color.primary.opacity(0.08),
            barHeight: 5,
            accessibilityLabel: "Codex Weekly"
        )
    }
    .padding()
    .frame(width: 320)
}
