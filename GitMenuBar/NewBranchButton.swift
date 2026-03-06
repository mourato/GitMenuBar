import AppKit
import SwiftUI

struct NewBranchButton: View {
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            Text("New Branch")
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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
