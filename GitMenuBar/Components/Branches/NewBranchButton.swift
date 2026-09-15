import SwiftUI

struct NewBranchButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("New Branch")
                    .font(.caption.weight(.medium))
                Spacer()
            }
        }
        .workbenchRow()
    }
}

#Preview("New Branch Button") {
    NewBranchButton(onTap: {})
        .frame(width: 200)
}
