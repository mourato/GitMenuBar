import SwiftUI

struct NewBranchButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                LucideIconView(name: .circlePlus, size: 12)
                    .foregroundStyle(Color.accentColor)
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
