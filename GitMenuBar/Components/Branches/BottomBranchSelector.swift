import AppKit
import SwiftUI

struct BottomBranchSelectorView: View {
    let currentBranch: String
    let commitCount: Int
    let isRemoteAhead: Bool
    let behindCount: Int
    let isDetachedHead: Bool
    let onTap: () -> Void
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .padding(.trailing, 4)

                    Text(currentBranch)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .animation(nil, value: currentBranch)
                .animation(nil, value: commitCount)

                HStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .padding(.trailing, 4)

                        Text("\(commitCount)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }

                    if isRemoteAhead {
                        HStack(spacing: 4) {
                            Divider()
                                .frame(width: 1, height: 6)
                                .background(Color.primary.opacity(0.12))

                            HStack(spacing: 0) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .padding(.trailing, 4)

                                Text("\(behindCount)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current branch \(currentBranch)")
        .accessibilityHint("Shows branch selection and sync actions.")
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
            return Color.red.opacity(colorSchemeContrast == .increased ? 0.28 : 0.16)
        }
        if isRemoteAhead || commitCount > 0 {
            return Color.orange.opacity(colorSchemeContrast == .increased ? 0.24 : 0.14)
        }
        return Color(nsColor: .controlBackgroundColor)
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
