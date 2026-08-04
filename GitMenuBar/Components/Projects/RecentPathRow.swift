import SwiftUI

struct RecentPathRowView: View {
    let displayText: String
    let fullPath: String
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 28

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "clock")
                    .font(WorkbenchTypography.detail)
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(WorkbenchTypography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fullPath)
                Spacer()
            }
            .frame(minHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

#Preview("Recent Path Row – Large Text") {
    RecentPathRowView(
        displayText: "A very long repository name that should truncate safely",
        fullPath: "~/Documents/Projects/a-very-long-repository-name",
        onTap: {}
    )
    .padding()
    .frame(width: 320)
    .dynamicTypeSize(.accessibility2)
}
