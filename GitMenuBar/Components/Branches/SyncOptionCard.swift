import SwiftUI

struct SyncOptionCard: View {
    let title: String
    let subtitle: String
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(backgroundColor)
            .cornerRadius(6)
        }
        .buttonStyle(.borderless)
    }
}
