import AppKit
import SwiftUI

struct BottomBranchSelectorView: View {
    let currentBranch: String
    let commitCount: Int
    let isRemoteAhead: Bool
    let behindCount: Int
    let isDetachedHead: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.trailing, 4)

                Text(currentBranch)
                    .font(.system(size: 11, weight: .medium, design: .rounded))

                Text(" ▲")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                Text("\(commitCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 12, alignment: .leading)

                if isRemoteAhead {
                    Text(" ▼")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text("\(behindCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                        .monospacedDigit()
                        .frame(minWidth: 12, alignment: .leading)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .clipShape(Capsule())
            .animation(nil, value: currentBranch)
            .animation(nil, value: commitCount)
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var backgroundColor: Color {
        if isDetachedHead {
            return Color.red.opacity(0.3)
        }
        if isRemoteAhead || commitCount > 0 {
            return Color.orange.opacity(0.2)
        }
        return Color.green.opacity(0.2)
    }
}

#Preview("Bottom Branch Selector") {
    BottomBranchSelectorView(
        currentBranch: "main",
        commitCount: 3,
        isRemoteAhead: true,
        behindCount: 1,
        isDetachedHead: false,
        onTap: {}
    )
    .padding()
}
