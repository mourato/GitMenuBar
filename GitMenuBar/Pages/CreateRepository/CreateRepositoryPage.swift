import SwiftUI

struct CreateRepositoryPageView: View {
    let folderPath: String
    let onCancel: () -> Void
    let onSuccess: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            InlinePageHeader(
                title: "Create Repository",
                systemImage: "plus.circle.fill",
                actionTitle: "Cancel",
                onAction: onCancel
            )

            Divider()
                .padding(.top, 4)

            CreateRepoContentView(
                folderPath: folderPath,
                onDismiss: onCancel,
                onSuccess: onSuccess
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
