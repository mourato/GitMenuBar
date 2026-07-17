import AppKit
import SwiftUI

struct RecentPathRowView: View {
    let displayText: String
    let fullPath: String
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 28

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "clock")
                    .font(MacChromeTypography.detail)
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(MacChromeTypography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fullPath)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(minHeight: rowHeight)
            .background(isHovered ? MacChromePalette.hoverFill() : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .animation(
            MacChromeMotion.adaptive(MacChromeMotion.micro, usesReducedMotion: reduceMotion),
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

#Preview("Recent Path Row") {
    RecentPathRowView(
        displayText: "gitmenubar",
        fullPath: "~/Documents/Repos/gitmenubar",
        onTap: {}
    )
    .padding()
    .frame(width: 320)
}

#Preview("Recent Path Row – Large Text") {
    RecentPathRowView(
        displayText: "A very long repository name that should truncate safely",
        fullPath: "~/Documents/Projects/a-very-long-repository-name",
        onTap: {}
    )
    .padding()
    .frame(width: 320)
    .dynamicTypeSize(.accessibility2)
}
