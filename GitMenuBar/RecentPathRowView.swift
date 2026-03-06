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
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fullPath)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.gray.opacity(0.15) : Color.gray.opacity(0.1))
            .cornerRadius(4)
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
