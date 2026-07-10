import SwiftUI

struct PullToNewBranchSheet: View {
    @Binding var branchName: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onPull: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Pull to New Branch")
                .font(.headline.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Branch name:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("branch-name", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline.monospaced())
                    .onSubmit(onPull)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Pull", action: onPull)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

private struct PullToNewBranchSheetPreviewContainer: View {
    @State private var branchName = "feature/sync-improvements"

    var body: some View {
        PullToNewBranchSheet(
            branchName: $branchName,
            errorMessage: nil,
            onCancel: {},
            onPull: {}
        )
    }
}

#Preview("Pull To New Branch Sheet") {
    PullToNewBranchSheetPreviewContainer()
}
