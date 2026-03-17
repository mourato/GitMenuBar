import SwiftUI

struct InlinePageHeader: View {
    let title: String
    let systemImage: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }

            Spacer()

            Button(actionTitle, action: onAction)
                .buttonStyle(.borderless)
                .focusable(false)
        }
        .padding(.top, 4)
    }
}

#Preview("Inline Page Header") {
    InlinePageHeader(
        title: "Settings",
        systemImage: "gear",
        actionTitle: "Done",
        onAction: {}
    )
    .padding()
    .frame(width: 360)
}
