import AppKit
import SwiftUI

struct NewBranchButton: View {
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                Text("New Branch")
                    .font(.caption.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? MacChromePalette.hoverFill() : Color.clear)
            .contentShape(Rectangle())
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

#Preview("New Branch Button") {
    NewBranchButton(onTap: {})
        .frame(width: 200)
}
