import AppKit
import SwiftUI

struct RecentPathRowView: View {
    let displayText: String
    let fullPath: String
    let onTap: () -> Void

    @State private var isHovered = false

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
            .frame(minHeight: 28)
            .background(isHovered ? MacChromePalette.hoverFill() : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
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
